# GCP infrastructure

Terraform configuration for the Python GKE platform.

## Layout

- `bootstrap`: versioned GCS bucket for Terraform state.
- `environments/prod`: main infrastructure configuration.
- `modules/networking`: custom VPC, subnet, secondary ranges, Cloud Router and Cloud NAT.
- `modules/iam`: dedicated GKE node service account.
- `modules/gke`: private GKE Standard cluster and node pool.
- `checks`: temporary Kubernetes verification manifests.

All commands below assume the repository root as the working directory.

## Prerequisites

- Terraform >= 1.6 and < 2.0.
- Google Cloud CLI.
- kubectl and gke-gcloud-auth-plugin.
- A dedicated GCP project with billing enabled.
- Permissions to create the configured GCP resources.

Authenticate the Google Cloud CLI and configure Application Default Credentials
for Terraform:

```bash
gcloud auth login
gcloud auth application-default login
```

## Bootstrap

Copy `bootstrap/terraform.tfvars.example` to
`bootstrap/terraform.tfvars` and fill in the project, region and bucket name.

Copy `bootstrap/backend.tfbackend.example` to
`bootstrap/backend.tfbackend` and set the same bucket name.

### Fresh deployment

The state bucket must exist before the GCS backend can be initialized.
For a fresh checkout and a new bucket, temporarily disable the backend
configuration and create the bucket using local state:

```bash
mv infra/bootstrap/backend.tf infra/bootstrap/backend.tf.disabled

terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
```

Restore the backend configuration and migrate the local state to GCS:

```bash
mv infra/bootstrap/backend.tf.disabled infra/bootstrap/backend.tf

terraform -chdir=infra/bootstrap init \
  -migrate-state \
  -backend-config=backend.tfbackend

terraform -chdir=infra/bootstrap plan
```

Confirm the state migration when prompted. The final plan should report
no changes.

### Existing deployment

When the bucket and remote state already exist, initialize directly:

```bash
terraform -chdir=infra/bootstrap init \
  -backend-config=backend.tfbackend

terraform -chdir=infra/bootstrap plan
```

Do not repeat the fresh-deployment procedure for an existing deployment.

## Main infrastructure

Copy the supplied examples:

```bash
cp infra/environments/prod/terraform.tfvars.example \
  infra/environments/prod/terraform.tfvars

cp infra/environments/prod/backend.tfbackend.example \
  infra/environments/prod/backend.tfbackend
```

Edit both local files before continuing:

- Set the GCP project, region and zone.
- Set `admin_cidr` to your public IPv4 address with a `/32` prefix.
- Set the state bucket and the `environments/prod` state prefix.

Initialize, validate and generate a plan:

```bash
terraform -chdir=infra/environments/prod init \
  -backend-config=backend.tfbackend

terraform -chdir=infra/environments/prod validate

terraform -chdir=infra/environments/prod plan \
  -out=infrastructure.tfplan
```

Review the plan, then apply it:

```bash
terraform -chdir=infra/environments/prod apply infrastructure.tfplan
```

## Cluster access

Configure kubectl using Terraform outputs:

```bash
gcloud container clusters get-credentials \
  "$(terraform -chdir=infra/environments/prod output -raw cluster_name)" \
  --zone="$(terraform -chdir=infra/environments/prod output -raw cluster_location)" \
  --project="$(terraform -chdir=infra/environments/prod output -raw project_id)"

kubectl get nodes -o wide
```

If your public IPv4 address changes, update `admin_cidr` in the local
`terraform.tfvars`, review a new Terraform plan and apply the access change.

## Design

- Zonal GKE Standard cluster in `europe-west1-b`.
- Two `e2-standard-2` nodes initially, with node autoscaling from two to three.
- Custom VPC with subnet `10.20.0.0/20`.
- Secondary ranges: `10.24.0.0/16` for Pods and `10.28.0.0/20` for Services.
- Nodes have private addresses only.
- External egress uses Cloud NAT with a Terraform-managed static IP.
- Public control-plane access is restricted to a developer IPv4 `/32`.
- Secure Boot and Integrity Monitoring are enabled.
- Workload Identity is enabled at the cluster and node-pool levels.
- Nodes use a dedicated service account with
  `roles/container.defaultNodeServiceAccount`.
- Application-specific IAM bindings are configured separately.
- The GCE Persistent Disk CSI driver is enabled.
- Bootstrap and main infrastructure use separate GCS state prefixes.

The single-zone cluster does not provide availability across a zone failure.
Cloud NAT provides outbound connectivity; it does not filter allowed
outbound destinations.

## JFrog integration

- Registry: `trialokuvu3.jfrog.io`.
- Docker repository: `docker-local`.
- Python proxy repository: `pypi-remote`.
- Application namespace used for verification: `platform-staging`.
- Kubernetes service account used for verification: `python-platform`.
- Registry secret: `jfrog-registry`.

Application image:

```text
trialokuvu3.jfrog.io/docker-local/python-gke-platform:local
```

Registry credentials are created outside Git. The Kubernetes service account
references the registry secret through `imagePullSecrets`.

Never commit the registry secret, tokens or a Docker configuration containing
credentials.

The pull-check manifest requires the namespace, service account and registry
secret to exist:

```bash
kubectl apply -f infra/checks/jfrog-pull-check.yaml

kubectl wait \
  --namespace=platform-staging \
  --for=condition=Ready \
  pod/jfrog-pull-check \
  --timeout=180s

kubectl exec -n platform-staging jfrog-pull-check -- \
  python -c '
import os
import urllib.request

print("UID:", os.getuid())
for path in ["/", "/healthz", "/ready"]:
    response = urllib.request.urlopen("http://127.0.0.1:8000" + path)
    print(path, response.status, response.read().decode())
'

kubectl get pod jfrog-pull-check \
  --namespace=platform-staging \
  -o jsonpath='{.status.containerStatuses[0].imageID}'

kubectl delete pod jfrog-pull-check --namespace=platform-staging
```

The temporary pull check uses `emptyDir` and does not test persistent storage.

## Verification

Check Terraform formatting, configuration and deployed state:

```bash
terraform fmt -check -recursive infra

terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan

terraform -chdir=infra/environments/prod validate
terraform -chdir=infra/environments/prod plan
```

Both plans should report no changes after deployment.

Check the cluster:

```bash
kubectl get nodes -o wide
kubectl get storageclass standard-rwo -o yaml
kubectl top nodes
```

Expected results:

- Nodes are Ready and have no external IP addresses.
- A test Pod's outbound public IP matches the Terraform `nat_ip` output.
- The JFrog pull-check Pod runs with UID `10001`.
- `/`, `/healthz` and `/ready` return HTTP 200.
- The running image digest matches the image published to JFrog.
- `standard-rwo` uses `pd.csi.storage.gke.io` and `WaitForFirstConsumer`.
- `kubectl top nodes` returns CPU and memory metrics.

PVC provisioning, application persistence and load testing are verified
during later deployment stages.

## State and cleanup

Do not commit Terraform state, saved plans, real `tfvars`, backend
configuration files or credentials. Commit Terraform provider lock files.

Keep the state bucket until the main infrastructure has been destroyed.

Before final infrastructure teardown, remove application resources that
provision cloud load balancers and disks, and verify their cleanup while
the cluster is still running.

The state bucket uses object versioning and `force_destroy = false`.
Final bucket cleanup must account for both current objects and older
object versions. Migrate bootstrap state out of the bucket before
destroying the bucket itself.

Cloud resources remain billable while provisioned. Budget alerts do not
automatically stop resources.
