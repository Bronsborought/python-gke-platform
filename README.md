# Python GKE Platform

A Python application delivery project using private Google Kubernetes Engine,
Terraform, GitHub Actions, JFrog Artifactory, Helm, and Argo CD.

## Repositories

- **python-gke-platform** — application, tests, Docker image, CI workflows,
  Terraform infrastructure, and setup/teardown scripts.
- [**python-gke-platform-gitops**](https://github.com/Bronsborought/python-gke-platform-gitops)
  — Helm charts, staging/production configuration, Argo CD applications,
  and monitoring configuration.

## Planned layout

- `app/` — Python application.
- `tests/` — application tests.
- `terraform/` — infrastructure configuration and modules.
- `scripts/` — setup, verification, and teardown scripts.
- `docs/` — architecture, operating instructions, and acceptance evidence.
- `.github/workflows/` — CI workflows.

## Status

Initial repository setup is in progress.
Application and cloud infrastructure have not been deployed.
