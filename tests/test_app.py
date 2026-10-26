import pytest
from fastapi.testclient import TestClient
from prometheus_client.parser import text_string_to_metric_families

from app.main import app


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("POD_NAME", "test-pod")
    with TestClient(app) as test_client:
        yield test_client


def test_root(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "environment": "test",
        "pod_name": "test-pod",
    }


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_ready(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_data_missing(client):
    response = client.get("/data")
    assert response.status_code == 404


def test_data_write_read_and_replace(client, tmp_path):
    for content in ["Привіт, Kubernetes!", "Updated content"]:
        response = client.post("/data", json={"content": content})
        assert response.status_code == 200
        assert response.json() == {"status": "saved"}

        response = client.get("/data")
        assert response.status_code == 200
        assert response.json() == {"content": content}

        saved_file = tmp_path / "data" / "payload.txt"
        assert saved_file.read_text(encoding="utf-8") == content


@pytest.mark.parametrize(
    "payload",
    [{}, {"content": 123}, {"content": "x" * 100_001}],
)
def test_invalid_data(client, payload):
    response = client.post("/data", json=payload)
    assert response.status_code == 422


def test_unavailable_storage(client, tmp_path, monkeypatch):
    blocked_path = tmp_path / "not-a-directory"
    blocked_path.write_text("This is a file")
    monkeypatch.setenv("DATA_DIR", str(blocked_path))

    assert client.get("/ready").status_code == 503
    assert client.get("/data").status_code == 503
    assert client.post("/data", json={"content": "test"}).status_code == 503
    assert client.get("/healthz").status_code == 200


def metric_value(text, name, labels):
    for family in text_string_to_metric_families(text):
        for sample in family.samples:
            if sample.name == name and sample.labels == labels:
                return sample.value
    return 0.0


def test_metrics(client):
    labels = {"method": "GET", "path": "/", "status_code": "200"}
    duration_labels = {"method": "GET", "path": "/"}

    response = client.get("/metrics")
    assert response.status_code == 200
    before = response.text

    assert client.get("/").status_code == 200
    after = client.get("/metrics").text

    counter = "http_requests_total"
    assert metric_value(after, counter, labels) == (
        metric_value(before, counter, labels) + 1
    )

    count = "http_request_duration_seconds_count"
    assert metric_value(after, count, duration_labels) == (
        metric_value(before, count, duration_labels) + 1
    )

    assert "http_request_duration_seconds_bucket{" in after

    repeated = client.get("/metrics").text
    assert metric_value(repeated, counter, labels) == (
        metric_value(after, counter, labels)
    )
