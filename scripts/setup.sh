#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${GITOPS_REPO:?Set GitOps checkout path}"
: "${GCP_PROJECT_ID:?Set project ID}"
: "${GKE_ZONE:?Set zone}"
: "${GKE_CLUSTER:?Set cluster name}"
for tool in terraform gcloud kubectl; do command -v "$tool" >/dev/null; done
for dir in bootstrap environments/prod; do
  test -f "$ROOT/infra/$dir/terraform.tfvars"
  test -f "$ROOT/infra/$dir/backend.tfbackend"
  terraform -chdir="$ROOT/infra/$dir" init -backend-config=backend.tfbackend
  terraform -chdir="$ROOT/infra/$dir" validate
  terraform -chdir="$ROOT/infra/$dir" plan -out=setup.tfplan
  terraform -chdir="$ROOT/infra/$dir" apply setup.tfplan
  rm "$ROOT/infra/$dir/setup.tfplan"
done
gcloud container clusters get-credentials "$GKE_CLUSTER" --zone "$GKE_ZONE" --project "$GCP_PROJECT_ID"
for ns in argocd platform-staging platform-production monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
for ns in platform-staging platform-production; do
  for secret in jfrog-registry python-platform-app; do
    kubectl get secret "$secret" -n "$ns" >/dev/null || {
      echo "Create external Secret $ns/$secret using README, then rerun"; exit 1;
    }
  done
done
kubectl get secret grafana-admin -n monitoring >/dev/null
kubectl apply --server-side -k "$GITOPS_REPO/bootstrap/argocd"
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl apply -f "$GITOPS_REPO/bootstrap/projects"
kubectl apply -f "$GITOPS_REPO/bootstrap/root-application.yaml"
kubectl get applications -n argocd
