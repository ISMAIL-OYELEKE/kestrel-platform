"""Lambda entry point. SQS invokes it with a batch of messages.

Each message is handled on its own. Failed ones are returned in batchItemFailures, so SQS retries only
those (and after maxReceiveCount moves them to the DLQ) instead of retrying the whole batch.
"""

import json
import logging

import psycopg

from . import db
from .config import load_settings
from .logs import configure_logging, request_id_var
from .messaging import LogNotifier, SnsNotifier
from .scoring import score_application

configure_logging()
log = logging.getLogger("kestrel.scorer")
settings = load_settings()

# Created once per Lambda container and reused across invocations.
_conn: psycopg.Connection | None = None


def _notifier():
    if settings.notify_topic_arn:
        import boto3

        return SnsNotifier(boto3.client("sns"), settings.notify_topic_arn)
    return LogNotifier()


notifier = _notifier()


def _connection() -> psycopg.Connection:
    global _conn
    if _conn is None or _conn.closed:
        _conn = db.connect(settings)
    return _conn


def handler(event, _context=None):
    global _conn
    failures = []
    for record in event.get("Records", []):
        token = request_id_var.set("-")
        try:
            body = json.loads(record["body"])
            request_id_var.set(body.get("request_id", "-"))
            score_application(_connection(), notifier, body["application_id"], request_id_var.get())
        except Exception as exc:
            log.exception("scoring_failed", extra={"message_id": record.get("messageId")})
            failures.append({"itemIdentifier": record["messageId"]})
            if isinstance(exc, psycopg.OperationalError):
                _conn = None  # drop a broken connection; the next message opens a new one
        finally:
            request_id_var.reset(token)
    return {"batchItemFailures": failures}
