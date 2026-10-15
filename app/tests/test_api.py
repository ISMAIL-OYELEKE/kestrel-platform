"""API tests against a real Postgres. The queue is a fake so no AWS is needed."""

import psycopg
import pytest
from fastapi.testclient import TestClient

from kestrel.api import create_app

from conftest import SAMPLE_BVN, FakeQueue, make_settings

VALID = {"applicant_name": "Ada Obi", "bvn": SAMPLE_BVN, "monthly_salary": 150000, "requested_amount": 300000}


@pytest.fixture
def queue():
    return FakeQueue()


@pytest.fixture
def client(database_url, protector, queue):
    app = create_app(make_settings(database_url), protector=protector, queue=queue)
    with TestClient(app) as c:
        yield c


def test_create_then_read(client, queue):
    created = client.post("/applications", json=VALID)
    assert created.status_code == 201
    body = created.json()
    assert body["status"] == "PENDING"
    assert created.headers["Location"] == f"/applications/{body['id']}"
    assert queue.sent[0]["application_id"] == body["id"]

    read = client.get(f"/applications/{body['id']}")
    assert read.status_code == 200
    assert read.json()["status"] == "PENDING"
    assert read.json()["applicant_name"] == "Ada Obi"


def test_bvn_never_in_responses_or_database(client, database_url, capsys):
    created = client.post("/applications", json=VALID)
    read = client.get(f"/applications/{created.json()['id']}")
    assert SAMPLE_BVN not in created.text
    assert SAMPLE_BVN not in read.text
    assert "bvn" not in read.json()

    with psycopg.connect(database_url) as conn:
        row = conn.execute("SELECT * FROM applications").fetchone()
    assert all(SAMPLE_BVN not in str(value) for value in row)
    assert all(SAMPLE_BVN.encode() not in bytes(value) for value in row if isinstance(value, (bytes, memoryview)))

    assert SAMPLE_BVN not in capsys.readouterr().out


def test_validation_errors_do_not_echo_the_bvn(client):
    bad = client.post("/applications", json={**VALID, "bvn": SAMPLE_BVN + "9"})
    assert bad.status_code == 422
    assert SAMPLE_BVN not in bad.text


def test_bvn_sent_as_a_number_is_rejected(client):
    # As a JSON number, a BVN starting with 0 would silently lose its leading zero.
    assert client.post("/applications", json={**VALID, "bvn": 22123456789}).status_code == 422


@pytest.mark.parametrize("field, value", [("monthly_salary", 0), ("requested_amount", -5), ("applicant_name", "  ")])
def test_invalid_values_rejected(client, field, value):
    assert client.post("/applications", json={**VALID, field: value}).status_code == 422


def test_unknown_application_is_404(client):
    assert client.get("/applications/6f1c2c51-6f62-4d5f-9a0e-2f2a5d6c1b11").status_code == 404


def test_request_id_is_echoed_and_forwarded_to_the_queue(client, queue):
    response = client.post("/applications", json=VALID, headers={"X-Request-ID": "trace-abc-1"})
    assert response.headers["X-Request-ID"] == "trace-abc-1"
    assert queue.sent[-1]["request_id"] == "trace-abc-1"


def test_unsafe_request_id_is_replaced(client):
    response = client.get("/health", headers={"X-Request-ID": "bad id with spaces"})
    assert response.headers["X-Request-ID"] != "bad id with spaces"


def test_queue_failure_returns_503_and_leaves_nothing_behind(database_url, protector):
    app = create_app(make_settings(database_url), protector=protector, queue=FakeQueue(fail=True))
    with TestClient(app) as c:
        assert c.post("/applications", json=VALID).status_code == 503
    with psycopg.connect(database_url) as conn:
        assert conn.execute("SELECT count(*) FROM applications").fetchone()[0] == 0


def test_health_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}
