# Python GKE Platform

A Python application delivery project using private Google Kubernetes Engine,
Terraform, GitHub Actions, JFrog Artifactory, Helm, and Argo CD.

## Repositories

- **python-gke-platform** — application, tests, Docker image, CI workflows,
  Terraform infrastructure, and setup/teardown scripts.
- [**python-gke-platform-gitops**](https://github.com/Bronsborought/python-gke-platform-gitops)
  — Helm charts, staging/production configuration, Argo CD applications,
  and monitoring configuration.

## Status

Implemented and verified:
- Python application and automated tests.
- Docker packaging with non-root execution and local persistent storage.
- GitHub Actions checks and vulnerability scanning.
- Terraform GCS backend, custom networking, Cloud NAT and private GKE nodes.
- JFrog Docker image publication and image pull from GKE.
- Python package download through the JFrog PyPI proxy.

Helm deployment, Argo CD delivery and cluster observability are next.

See [GCP infrastructure](infra/README.md) for infrastructure setup,
access, verification and cleanup guidance.

## Local setup

Run these commands from the repository root with Python 3.14 installed:

```bash
python3.14 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
```

`requirements.txt` contains runtime dependencies.
`requirements-dev.txt` contains runtime and development dependencies.

## Run locally

```bash
APP_ENV=local DATA_DIR=./data LOG_LEVEL=INFO \
python -m uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 8000 \
  --reload
```

The reload option is intended for local development.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | Application status, environment, and pod name |
| GET | `/healthz` | Process liveness |
| GET | `/ready` | Storage write/read readiness check |
| POST | `/data` | Save text from a JSON `content` field |
| GET | `/data` | Read the saved text |
| GET | `/metrics` | Prometheus metrics |

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_ENV` | `local` | Environment name |
| `POD_NAME` | System hostname | Pod identifier |
| `DATA_DIR` | `./data` | Storage directory |
| `LOG_LEVEL` | `INFO` | Application logging level |

## Verify data storage

With the server running:

```bash
curl -i http://127.0.0.1:8000/ready

curl -i -X POST http://127.0.0.1:8000/data \
  -H 'Content-Type: application/json' \
  -d '{"content":"Hello from python-gke-platform"}'

curl -i http://127.0.0.1:8000/data
```

Each POST replaces the previous content in `DATA_DIR/payload.txt`.
The content field accepts at most 100,000 characters.
Writes use a temporary file followed by an atomic replacement.

Data survives application restarts when the same storage directory is used.
Container and Kubernetes persistence require a mounted persistent volume.

GET `/data` returns 404 when no data has been saved.
Storage failures return 503; invalid request bodies return 422.

## Metrics

- `http_requests_total` — request count by method, route, and status code.
- `http_request_duration_seconds` — request duration histogram by method and route.

Requests to `/metrics` are excluded from these measurements.
Metrics are held in process memory and reset on restart.
The current implementation uses one application worker per instance.

## Checks and tests

```bash
python -m black --check app tests
python -m flake8 app tests
python -m pytest -v --junitxml=junit.xml
```

Tests use temporary storage and do not modify local application data.

## Planned layout

- `app/` — Python application.
- `tests/` — application tests.
- `infra/` — infrastructure configuration, modules and verification manifests.
- `scripts/` — setup, verification, and teardown scripts.
- `docs/` — architecture, operating instructions, and acceptance evidence.
- `.github/workflows/` — CI workflows.

## Local Docker run

Build the image:

```bash
docker build -t python-gke-platform:local .
```

The image uses Python 3.14 slim and a multi-stage build.
The application runs as UID/GID 10001 without root privileges.
The locally verified linux/amd64 image size was 194.10 MB.

Create persistent storage and start the container:

```bash
docker volume create python-gke-platform-data

docker run -d \
  --name python-gke-platform-local \
  -p 127.0.0.1:8001:8000 \
  -e APP_ENV=local \
  --mount type=volume,source=python-gke-platform-data,target=/data \
  python-gke-platform:local
```

The application is available at http://127.0.0.1:8001.
The container defaults to PORT=8000 and DATA_DIR=/data.
If PORT is overridden, update the container port mapping accordingly.

Wait for readiness:

```bash
curl --retry 10 --retry-all-errors --retry-delay 1 \
  --max-time 3 --retry-max-time 20 \
  -fsS http://127.0.0.1:8001/ready
```

Write and read data:

```bash
curl -fsS -X POST http://127.0.0.1:8001/data \
  -H 'Content-Type: application/json' \
  -d '{"content":"Hello from Docker volume"}'

curl -fsS http://127.0.0.1:8001/data
```

Inspect logs and metrics:

```bash
docker logs --tail 30 python-gke-platform-local
curl -fsS http://127.0.0.1:8001/metrics
```

Stop and remove the container:

```bash
docker stop python-gke-platform-local
docker rm python-gke-platform-local
```

The named volume remains after container removal. Run the same
`docker run` command again to reuse the saved data.

To permanently delete the stored data after removing the container:

```bash
docker volume rm python-gke-platform-data
```

## Raspberry Pi CM5 hybrid edge

Initial hardware and operating system setup verified:
- Compute module: Raspberry Pi Compute Module 5 Lite Rev 1.0 (8 GB RAM, no onboard eMMC).
- Carrier board: Waveshare CM5-IO-BASE-B with passive heatsink, external SMA antenna (`dtparam=ant2`), and official 27W USB-C power supply (`throttled=0x0`).
- Storage: 512 GB M.2 2230 PCIe NVMe SSD (`/dev/nvme0n1`, 476.9 GiB usable, Biwin/KingSpec controller supporting PCIe Gen 3 `8GT/s`, initial link `5GT/s`).
- Operating system: Ubuntu Server 24.04.5 LTS (`aarch64`, kernel `6.8.0-1064-raspi`), hostname `cm5-node`.
- Access and network: Ed25519 SSH key authentication, passwordless `sudo`, and MAC-based DHCP lease over Wi-Fi (`wlan0`) and Ethernet (`eth0`).

Storage layout decision for ZFS:
- Because the module is a CM5 Lite without onboard eMMC, the operating system boots from `/dev/nvme0n1` (`nvme0n1p1` `/boot/firmware` and `nvme0n1p2` `/`).
- Using the whole `/dev/nvme0n1` device directly for `zpool create` would overwrite the running OS; therefore, the NVMe SSD will be partitioned so the OS remains on `nvme0n1p1`/`nvme0n1p2` and the ZFS pool `datapool` uses a dedicated partition (`/dev/nvme0n1p3`) on the same NVMe drive.

Next steps (not yet executed):
- Module 1: Ansible bootstrap (`ansible/rpi-cm5-bootstrap.yml`).
- Module 2: ZFS pool `datapool`, datasets/quotas, NFSv4 export, and encrypted GCS backups.
- Module 3: Site-to-cloud WireGuard VPN tunnel to GCP VPC.
- Module 4: Native ARM64 GitHub Actions runner and multi-arch publishing to JFrog Artifactory.
- Module 5: K3s edge node managed by central Argo CD in GKE.
- Module 6: Hardware metrics (`node_exporter` + textfile collector) in Prometheus and Grafana.
