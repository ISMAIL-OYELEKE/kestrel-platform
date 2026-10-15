"""Scorer tests against a real Postgres: decisions, idempotency and partial batch failures."""

import json
import threading
import uuid
from decimal import Decimal

import psycopg
import pytest

from kestrel import repository, scorer
from kestrel.scoring import ApplicationNotFound, score_application

from conftest import SAMPLE_BVN, FakeNotifier


def _insert(database_url, protector, salary="100000", amount="250000") -> str:
    application_id = str(uuid.uuid4())
    with psycopg.connect(database_url) as conn:
        repository.insert_application(
            conn,
            application_id=application_id,
            applicant_name="Test",
            bvn_ciphertext=protector.encrypt(SAMPLE_BVN, application_id),
            bvn_lookup_hash=protector.lookup_hash(SAMPLE_BVN),
            monthly_salary=Decimal(salary),
            requested_amount=Decimal(amount),
            request_id="req-1",
        )
    return application_id


def _status(database_url, application_id):
    with psycopg.connect(database_url) as conn:
        return conn.execute("SELECT status FROM applications WHERE id = %s", (application_id,)).fetchone()[0]


@pytest.mark.parametrize("amount, expected", [("300000", "APPROVED"), ("300001", "DECLINED")])
def test_scores_and_notifies(database_url, protector, amount, expected):
    application_id = _insert(database_url, protector, amount=amount)
    notifier = FakeNotifier()
    with psycopg.connect(database_url) as conn:
        assert score_application(conn, notifier, application_id, "req-1") == expected
    assert _status(database_url, application_id) == expected
    assert [e["decision"] for e in notifier.events] == [expected]
    assert notifier.events[0]["request_id"] == "req-1"
    assert SAMPLE_BVN not in json.dumps(notifier.events)


def test_same_message_twice_gives_one_decision(database_url, protector):
    application_id = _insert(database_url, protector)
    notifier = FakeNotifier()
    with psycopg.connect(database_url) as conn:
        score_application(conn, notifier, application_id, "req-1")
        score_application(conn, notifier, application_id, "req-1")
    assert len(notifier.events) == 1


def test_concurrent_duplicates_give_one_decision(database_url, protector):
    # The incident 2 scenario: a message becomes visible again while the first copy is still running.
    application_id = _insert(database_url, protector)
    notifier = FakeNotifier()
    errors = []

    def worker():
        try:
            with psycopg.connect(database_url) as conn:
                score_application(conn, notifier, application_id, "req-1")
        except Exception as exc:  # pragma: no cover
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert not errors
    assert len(notifier.events) == 1


def test_failed_notification_rolls_back_and_retry_succeeds(database_url, protector):
    application_id = _insert(database_url, protector)
    notifier = FakeNotifier(fail_times=1)
    with psycopg.connect(database_url) as conn:
        with pytest.raises(RuntimeError):
            score_application(conn, notifier, application_id, "req-1")
        assert _status(database_url, application_id) == "PENDING"
        assert score_application(conn, notifier, application_id, "req-1") == "APPROVED"
    assert len(notifier.events) == 1


def test_missing_application_raises_so_message_is_retried(database_url):
    with psycopg.connect(database_url) as conn:
        with pytest.raises(ApplicationNotFound):
            score_application(conn, FakeNotifier(), str(uuid.uuid4()), "req-1")


def test_lambda_handler_reports_only_failed_messages(database_url, protector, monkeypatch):
    good = _insert(database_url, protector)
    notifier = FakeNotifier()
    monkeypatch.setattr(scorer, "notifier", notifier)
    monkeypatch.setattr(scorer, "_conn", psycopg.connect(database_url))
    event = {
        "Records": [
            {"messageId": "m1", "body": json.dumps({"application_id": good, "request_id": "req-9"})},
            {"messageId": "m2", "body": json.dumps({"application_id": str(uuid.uuid4()), "request_id": "req-9"})},
            {"messageId": "m3", "body": "not json"},
        ]
    }
    result = scorer.handler(event)
    assert result == {"batchItemFailures": [{"itemIdentifier": "m2"}, {"itemIdentifier": "m3"}]}
    assert notifier.events[0]["request_id"] == "req-9"
