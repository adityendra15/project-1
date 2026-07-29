from pathlib import Path

import pytest

from app.main import NOT_READY_FILE, create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(TESTING=True)
    with app.test_client() as test_client:
        yield test_client
    NOT_READY_FILE.unlink(missing_ok=True)


def test_home_page_contains_project_identity(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Secure Delivery Pipeline" in response.data


def test_liveness_endpoint(client):
    response = client.get("/health/live")
    payload = response.get_json()
    assert response.status_code == 200
    assert payload["status"] == "alive"
    assert payload["uptime_seconds"] >= 0


def test_readiness_endpoint_is_independent_from_liveness(client):
    NOT_READY_FILE.touch()

    readiness_response = client.get("/health/ready")
    liveness_response = client.get("/health/live")

    assert readiness_response.status_code == 503
    assert readiness_response.get_json()["status"] == "not-ready"
    assert liveness_response.status_code == 200


def test_version_endpoint(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "test-version")
    monkeypatch.setenv("COMMIT_SHA", "abc123")
    version_client = create_app().test_client()

    response = version_client.get("/version")
    payload = response.get_json()

    assert response.status_code == 200
    assert payload["version"] == "test-version"
    assert payload["commit_sha"] == "abc123"
    assert payload["hostname"]


def test_security_headers_are_present(client):
    response = client.get("/")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "frame-ancestors 'none'" in response.headers["Content-Security-Policy"]


def test_unknown_route_returns_json(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert response.get_json() == {"error": "not_found", "path": "/does-not-exist"}
