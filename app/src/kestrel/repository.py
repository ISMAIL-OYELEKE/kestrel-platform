"""Every SQL statement the API and the scorer run. Parameters are always bound, never formatted into SQL."""

from decimal import Decimal

import psycopg
from psycopg.rows import dict_row

# Columns safe to return to a caller. The BVN columns are deliberately not here.
PUBLIC_COLUMNS = "id, applicant_name, monthly_salary, requested_amount, status, created_at, decided_at"


def insert_application(
    conn: psycopg.Connection,
    *,
    application_id: str,
    applicant_name: str,
    bvn_ciphertext: bytes,
    bvn_lookup_hash: bytes,
    monthly_salary: Decimal,
    requested_amount: Decimal,
    request_id: str,
) -> None:
    conn.execute(
        """INSERT INTO applications
               (id, applicant_name, bvn_ciphertext, bvn_lookup_hash, monthly_salary, requested_amount, request_id)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (application_id, applicant_name, bvn_ciphertext, bvn_lookup_hash, monthly_salary, requested_amount, request_id),
    )


def delete_application(conn: psycopg.Connection, application_id: str) -> None:
    conn.execute("DELETE FROM applications WHERE id = %s AND status = 'PENDING'", (application_id,))


def get_application(conn: psycopg.Connection, application_id: str) -> dict | None:
    with conn.cursor(row_factory=dict_row) as cur:
        # The f-string only inserts a fixed constant column list; the id is still a bound parameter.
        cur.execute(f"SELECT {PUBLIC_COLUMNS} FROM applications WHERE id = %s", (application_id,))  # noqa: S608
        return cur.fetchone()


def lock_for_scoring(conn: psycopg.Connection, application_id: str) -> dict | None:
    """Row lock held until the transaction ends. A second copy of the same message waits here, then
    sees the first copy's result, which is what stops two decisions for one application."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """SELECT id, status, monthly_salary, requested_amount, decided_at, notified_at
               FROM applications WHERE id = %s FOR UPDATE""",
            (application_id,),
        )
        return cur.fetchone()


def record_decision(conn: psycopg.Connection, application_id: str, decision: str):
    """Returns the decision time. The WHERE clause makes this a no-op if a decision already exists."""
    row = conn.execute(
        """UPDATE applications SET status = %s, decided_at = now()
           WHERE id = %s AND status = 'PENDING' RETURNING decided_at""",
        (decision, application_id),
    ).fetchone()
    return row[0] if row else None


def mark_notified(conn: psycopg.Connection, application_id: str) -> None:
    conn.execute("UPDATE applications SET notified_at = now() WHERE id = %s", (application_id,))


def ping(conn: psycopg.Connection) -> None:
    conn.execute("SELECT 1")
