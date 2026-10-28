# Python platform Helm chart

## Required external Secrets

Create these separately in each target namespace:

- `jfrog-registry`: kubernetes.io/dockerconfigjson credentials.
- `python-platform-app`: Opaque Secret with an API_KEY entry.

The current application receives API_KEY but does not enforce HTTP
authentication using it.

## Environments

- platform-staging: staging values, accessed through port-forward.
- platform-production: production values, external GKE HTTP Ingress.

Each namespace has its own application PVC and Secrets.

## Deployment

```bash
helm upgrade --install python-platform charts/python-platform \
  --namespace platform-staging \
  -f charts/python-platform/values-staging.yaml \
  --wait --timeout 10m
```

Use platform-production and values-production.yaml for production.

## Storage limitation

The chart uses a standard-rwo Persistent Disk and required pod affinity
to colocate replicas of a release on one node.

All replicas share the same payload file. The latest successful write
replaces previous content.

This supports shared data for colocated replicas, but does not provide
application availability across a node failure. Node drain can be
constrained by the combination of affinity, storage attachment and PDB.

A multi-node HA design requires a separate storage decision, such as
RWX storage or an application data service. Do not describe the current
configuration as resilient to node or zone failure.

## Probes and resources

- Startup and liveness: /healthz.
- Readiness and load-balancer health check: /ready.
- HPA: 2–5 replicas, CPU 70%, memory 80%.
- PDB: minAvailable 1.
- Non-root UID/GID 10001, read-only root filesystem.

## Validation

- helm lint and template rendering.
- Kubernetes server-side dry run.
- Healthy endpoints in both environments.
- Shared data across replicas.
- Data retained after a Deployment rollout restart.
- Helm upgrade and rollback.

A full load test is still required to prove HPA scale-out and
zero-downtime releases.

## Lifecycle

Deleting pods does not delete the PVC.
Uninstalling this chart deletes its PVC and can cause data loss.

Remove Ingress and other load-balancer resources while the cluster
still exists during final teardown, allowing the GKE controller to
clean up cloud resources.

The local image tag is temporary. The delivery pipeline will introduce
versioned image tags.

## GitOps handover

Before ArgoCD manages this chart, record the existing release resources
and establish one deployment owner. Do not run manual Helm upgrades
against an environment after ArgoCD has taken over reconciliation.
