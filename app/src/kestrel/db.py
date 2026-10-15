"""Database connections. In AWS the password is read from Secrets Manager at connect time, so a
rotated password is picked up by new connections without a redeploy."""

import json
import time

import psycopg

from .config import Settings

SCHEMA = """
CREATE TABLE IF NOT EXISTS applications (
    id               uuid PRIMARY KEY,
    applicant_name   text           NOT NULL,
    bvn_ciphertext   bytea          NOT NULL,
    bvn_lookup_hash  bytea          NOT NULL,
    monthly_salary   numeric(14, 2) NOT NULL CHECK (monthly_salary > 0),
    requested_amount numeric(14, 2) NOT NULL CHECK (requested_amount > 0),
    status           text           NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING', 'APPROVED', 'DECLINED')),
    created_at       timestamptz    NOT NULL DEFAULT now(),
    decided_at       timestamptz,
    notified_at      timestamptz,
    request_id       text
);
CREATE INDEX IF NOT EXISTS applications_bvn_lookup_idx ON applications (bvn_lookup_hash);
"""

_SECRET_TTL_SECONDS = 60
_secret_cache: dict = {"value": None, "fetched_at": 0.0}


def _db_secret(settings: Settings) -> dict:
    now = time.monotonic()
    if _secret_cache["value"] is None or now - _secret_cache["fetched_at"] > _SECRET_TTL_SECONDS:
        import boto3

        raw = boto3.client("secretsmanager").get_secret_value(SecretId=settings.db_secret_arn)
        _secret_cache["value"] = json.loads(raw["SecretString"])
        _secret_cache["fetched_at"] = now
    return _secret_cache["value"]


def conninfo(settings: Settings) -> str:
    return settings.database_url or ""


def connection_kwargs(settings: Settings) -> dict:
    """Arguments for a new connection. Called once per new connection, never cached in the pool."""
    if settings.database_url:
        return {}
    secret = _db_secret(settings)
    return {
        "host": settings.db_host,
        "port": settings.db_port,
        "dbname": settings.db_name,
        "user": secret["username"],
        "password": secret["password"],
        "sslmode": settings.db_sslmode,
        "connect_timeout": 5,
    }


def forget_cached_secret() -> None:
    """After an authentication failure the password may have just rotated: fetch it again next time."""
    _secret_cache["value"] = None


def connect(settings: Settings) -> psycopg.Connection:
    try:
        return psycopg.connect(conninfo(settings), **connection_kwargs(settings))
    except psycopg.OperationalError:
        forget_cached_secret()
        raise


def ensure_schema(conn: psycopg.Connection) -> None:
    with conn.transaction():
        conn.execute(SCHEMA)
