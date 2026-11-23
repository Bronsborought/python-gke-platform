#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${GCP_PROJECT_ID:?Set dedicated project ID}"
: "${GKE_ZONE:?Set zone}"
: "${GKE_CLUSTER:?Set cluster}"
EXPECTED="gke_${GCP_PROJECT_ID}_${GKE_ZONE}_${GKE_CLUSTER}"
[[ "$(kubectl config current-context)" == "$EXPECTED" ]] || {
  echo 'Wrong Kubernetes context'; exit 1;
}
read -r -p "Type project ID to delete its platform resources: " CONFIRM
[[ "$CONFIRM" == "$GCP_PROJECT_ID" ]] || exit 1
BACKUP=$(mktemp -d "$HOME/platform-state-backup.XXXXXX")
chmod 700 "$BACKUP"
terraform -chdir="$ROOT/infra/environments/prod" state pull > "$BACKUP/prod.tfstate"
terraform -chdir="$ROOT/infra/bootstrap" state pull > "$BACKUP/bootstrap.tfstate"
chmod 600 "$BACKUP"/*.tfstate
kubectl patch application platform-root -n argocd --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' || true
for app in python-platform-staging python-platform-production platform-monitoring platform-observability edge-ingestion-service; do
  if kubectl get application "$app" -n argocd >/dev/null 2>&1; then
    kubectl patch application "$app" -n argocd --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}'
  fi
done
kubectl delete ingress python-platform -n platform-production --ignore-not-found --wait=true --timeout=10m
kubectl delete application platform-root -n argocd --ignore-not-found
kubectl delete applications python-platform-staging python-platform-production platform-monitoring platform-observability edge-ingestion-service \
  -n argocd --ignore-not-found
kubectl delete namespace platform-staging platform-production monitoring --ignore-not-found --wait=true --timeout=15m
clean=false
for attempt in $(seq 1 60); do
  count=$(gcloud compute forwarding-rules list --project "$GCP_PROJECT_ID" --format=json |
    python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  if [[ "$count" == 0 ]]; then clean=true; break; fi
  echo 'Waiting for forwarding rules cleanup'
  sleep 10
done
[[ "$clean" == true ]] || { echo 'Load balancer cleanup incomplete; inspect before Terraform destroy'; exit 1; }
terraform -chdir="$ROOT/infra/environments/prod" destroy -auto-approve
if [[ "${DELETE_STATE_BUCKET:-0}" == 1 ]]; then
  : "${STATE_BUCKET:?Set verified dedicated state bucket}"
  [[ "$STATE_BUCKET" == "$GCP_PROJECT_ID"* ]] || exit 1
  [[ -z "$(terraform -chdir="$ROOT/infra/environments/prod" state list)" ]] || exit 1
  test -f "$ROOT/infra/bootstrap/backend.tf"
  gcloud storage buckets describe "gs://$STATE_BUCKET" --format=json > "$BACKUP/bucket.json"
  mv "$ROOT/infra/bootstrap/backend.tf" "$ROOT/infra/bootstrap/backend.tf.disabled"
  trap 'if [[ -f "$ROOT/infra/bootstrap/backend.tf.disabled" ]]; then mv "$ROOT/infra/bootstrap/backend.tf.disabled" "$ROOT/infra/bootstrap/backend.tf"; fi' EXIT
  terraform -chdir="$ROOT/infra/bootstrap" init -migrate-state -force-copy -input=false
  test -s "$ROOT/infra/bootstrap/terraform.tfstate"
  cp "$ROOT/infra/bootstrap/terraform.tfstate" "$BACKUP/bootstrap-local.tfstate"
  chmod 600 "$BACKUP/bootstrap-local.tfstate"
  gcloud storage rm --all-versions "gs://$STATE_BUCKET/**"
  terraform -chdir="$ROOT/infra/bootstrap" destroy -auto-approve
  mv "$ROOT/infra/bootstrap/backend.tf.disabled" "$ROOT/infra/bootstrap/backend.tf"
  trap - EXIT
fi
echo "Cleanup completed for selected scope. Evidence: $BACKUP"
