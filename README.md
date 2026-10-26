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

The application has been implemented and tested locally with Python 3.14.
Docker packaging, cloud infrastructure, and GitOps delivery are not yet implemented.

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
- `terraform/` — infrastructure configuration and modules.
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
