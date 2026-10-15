"""The business rule and the idempotent decision step, shared by the Lambda handler and the local worker."""

import logging
from decimal import Decimal

import psycopg

from . import repository

log = logging.getLogger(__name__)

APPROVAL_MULTIPLE = Decimal(3)


class ApplicationNotFound(Exception):
    """Raised so the message is retried: the row may not be committed yet, or it will end in the DLQ."""


def decide(monthly_salary: Decimal, requested_amount: Decimal) -> str:
    return "APPROVED" if requested_amount <= APPROVAL_MULTIPLE * monthly_salary else "DECLINED"


def score_application(conn: psycopg.Connection, notifier, application_id: str, request_id: str) -> str:
    """Decide once, notify at least once, never two different decisions.

    Everything runs in one transaction holding a row lock:
    1. Lock the row. A duplicate delivery of the same message waits here.
    2. If still PENDING, apply the rule and store the decision.
    3. If a notification was already sent for this decision, stop (this was a duplicate).
    4. Publish the notification, then record that it was sent, then commit.
    If publishing fails, the transaction rolls back and the message is retried; the rule is
    deterministic, so the retry reaches the same decision.
    """
    with conn.transaction():
        row = repository.lock_for_scoring(conn, application_id)
        if row is None:
            raise ApplicationNotFound(application_id)

        status = row["status"]
        decided_at = row["decided_at"]
        if status == "PENDING":
            status = decide(row["monthly_salary"], row["requested_amount"])
            decided_at = repository.record_decision(conn, application_id, status)
            log.info("decision_made", extra={"application_id": application_id, "decision": status})

        if row["notified_at"] is not None:
            log.info("duplicate_message_ignored", extra={"application_id": application_id, "decision": status})
            return status

        notifier.publish(
            {
                "type": "loan.decision",
                "application_id": application_id,
                "decision": status,
                "decided_at": decided_at.isoformat(),
                "request_id": request_id,
            }
        )
        repository.mark_notified(conn, application_id)
        log.info("decision_notified", extra={"application_id": application_id, "decision": status})
        return status
