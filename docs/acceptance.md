# Platform Acceptance Matrix (GKE & Raspberry Pi CM5 Hybrid Edge)

## 1. Core GKE Cloud Platform Acceptance Criteria (`AC-01` .. `AC-12`)

| ID | Criterion | Result & Notes | Evidence Path / Reference | Date (UTC) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`AC-01`** | Private GKE nodes (`EXTERNAL-IP: <none>`) behind Cloud NAT & custom VPC (`10.20.0.0/20`) | 2 worker nodes (`10.20.0.8`, `10.20.0.9`) running without external IPs; control plane restricted by `/32` CIDR | [`docs/evidence/private-nodes.txt`](evidence/private-nodes.txt), `infra/environments/prod/` | 2026-11-23 | **Passed** |
| **`AC-02`** | Remote Terraform state in versioned GCS bucket | State stored in `gs://python-gke-dt-20261027-tfstate` with versioning and uniform bucket-level access | `infra/bootstrap/main.tf` | 2026-11-11 | **Passed** |
| **`AC-03`** | GKE Workload Identity keyless GCS access from pods | Pods authenticate to `gs://python-gke-dt-20261027-app-config` via Workload Identity SA without JSON keys | `infra/environments/prod/iam.tf` | 2026-11-11 | **Passed** |
| **`AC-04`** | Hardened multi-stage rootless container (`10001:10001`) | Base image pinned by SHA256 digest, offline wheel install, non-root `USER 10001:10001`, read-only rootfs | [`Dockerfile`](../Dockerfile) | 2026-11-17 | **Passed** |
| **`AC-05`** | Multi-Arch OCI image published to JFrog Artifactory | `linux/amd64` + native `linux/arm64` OCI index in `trial2mrxfh.jfrog.io/docker-local/python-platform-app:v1.2.0` | [`docs/evidence/ac-rpi-07-jfrog-multiarch.txt`](evidence/ac-rpi-07-jfrog-multiarch.txt) | 2026-11-17 | **Passed** |
| **`AC-06`** | Automated CI quality & security gates (`pytest`, `flake8`, `black`, `pip-audit`, `hadolint`, `trivy`) | Full CI and Release pipelines enforce unit tests, dependency CVE audit, Dockerfile lint, and Trivy scan | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), [`.github/workflows/release.yml`](../.github/workflows/release.yml) | 2026-11-23 | **Passed** |
| **`AC-07`** | Automated GitOps promotion & zero cluster access from CI | `scripts/promote.py` updates image digest in GitOps repo; Argo CD pulls changes in-cluster (`Synced / Healthy`) | [`docs/evidence/argocd-final.txt`](evidence/argocd-final.txt), [`scripts/promote.py`](../scripts/promote.py) | 2026-11-23 | **Passed** |
| **`AC-08`** | Zero-error HTTP traffic & PVC persistence validation | 329/329 HTTP 200 responses recorded by `scripts/http-load.py`; `/data` marker persisted across pod restarts | [`docs/evidence/staging-smoke-load.json`](evidence/staging-smoke-load.json) | 2026-11-23 | **Passed** |
| **`AC-09`** | Horizontal Pod Autoscaler (HPA) & PodDisruptionBudget | HPA (`2..6` replicas, CPU 70%) and PDB configured in Helm chart (`RWO` colocation constraint documented) | `python-gke-platform-gitops/charts/python-platform/` | 2026-11-23 | **Passed** |
| **`AC-10`** | Prometheus scraping (`15s`) & Grafana dashboards | `ServiceMonitor` scrapes `/metrics`; 8-panel app dashboard and 4-panel edge hardware dashboard provisioned | [`docs/evidence/app-observability-verification.txt`](evidence/app-observability-verification.txt) | 2026-11-23 | **Passed** |
| **`AC-11`** | PrometheusRule alerting (`HighErrorRate`, `PodCrashLooping`, `HighDiskUtilization`) | Application and hardware alert rules active and evaluated in Prometheus `/api/v1/rules` | [`docs/evidence/app-observability-verification.txt`](evidence/app-observability-verification.txt) | 2026-11-23 | **Passed** |
| **`AC-12`** | Reproducible setup & safe teardown lifecycle scripts | `scripts/setup.sh` and `scripts/teardown.sh` validated (`bash -n`); cloud billing unlinked after verification | [`scripts/setup.sh`](../scripts/setup.sh), [`scripts/teardown.sh`](../scripts/teardown.sh) | 2026-11-23 | **Passed** |

---

## 2. Raspberry Pi CM5 Hybrid Edge Extension Criteria (`AC-RPI-01` .. `AC-RPI-09`)

| ID | Module | Criterion | Evidence File | Date (UTC) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`AC-RPI-01`** | Module 1 | Idempotent Ansible bare-metal bootstrap (`changed=0`), PCIe Gen3, ZRAM, UFW | [`docs/evidence/ac-rpi-01-ansible.txt`](evidence/ac-rpi-01-ansible.txt) | 2026-11-11 | **Passed** |
| **`AC-RPI-02`** | Module 2 | ZFS pool `datapool` on NVMe (`zstd`, `50G`/`20G` quotas, hourly snapshots) | [`docs/evidence/ac-rpi-02-zfs.txt`](evidence/ac-rpi-02-zfs.txt) | 2026-11-11 | **Passed** |
| **`AC-RPI-03`** | Module 2 | Local LAN NFSv4 export (`/srv/data/annotation`) & client read/write test | [`docs/evidence/ac-rpi-03-nfs.txt`](evidence/ac-rpi-03-nfs.txt) | 2026-11-11 | **Passed** |
| **`AC-RPI-04`** | Module 2 | AES-256 encrypted ZFS snapshot backups to GCS with 90d Coldline lifecycle | [`docs/evidence/ac-rpi-04-gcs-backup.txt`](evidence/ac-rpi-04-gcs-backup.txt) | 2026-11-11 | **Passed** |
| **`AC-RPI-05`** | Module 3 | Site-to-Cloud L3 WireGuard VPN (`10.200.0.2` ↔ GCP VPC) without NAT masquerading | [`docs/evidence/ac-rpi-05-wireguard.txt`](evidence/ac-rpi-05-wireguard.txt) | 2026-11-17 | **Passed** |
| **`AC-RPI-06`** | Module 4 | Native ARM64 GitHub Actions self-hosted runner on RPi CM5 (`13s` build) | [`docs/evidence/ac-rpi-06-arm64-ci.txt`](evidence/ac-rpi-06-arm64-ci.txt) | 2026-11-17 | **Passed** |
| **`AC-RPI-07`** | Module 4 | Multi-Arch OCI manifest (`linux/amd64` + `linux/arm64`) in JFrog Artifactory | [`docs/evidence/ac-rpi-07-jfrog-multiarch.txt`](evidence/ac-rpi-07-jfrog-multiarch.txt) | 2026-11-17 | **Passed** |
| **`AC-RPI-08`** | Module 5 | Edge K3s cluster managed by GKE Argo CD over WireGuard with ZFS volume mount | [`docs/evidence/ac-rpi-08-edge-gitops.txt`](evidence/ac-rpi-08-edge-gitops.txt) | 2026-11-17 | **Passed** |
| **`AC-RPI-09`** | Module 6 | Bare-metal SoC thermal, 27W PD, NVMe SMART & ZFS observability in Prometheus/Grafana | [`docs/evidence/ac-rpi-09-hardware-monitoring.txt`](evidence/ac-rpi-09-hardware-monitoring.txt) | 2026-11-17 | **Passed** |
