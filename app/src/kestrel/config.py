"""All settings come from environment variables, so the same image runs locally, in dev and in prod."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    # Database: either a full URL (local) or host/name plus a Secrets Manager secret (AWS).
    database_url: str | None
    db_host: str | None
    db_port: int
    db_name: str
    db_secret_arn: str | None
    db_sslmode: str
    db_pool_max: int

    # Messaging
    queue_url: str | None
    sqs_endpoint_url: str | None
    notify_topic_arn: str | None

    # BVN protection: "kms" in AWS, "local" only for laptops and tests.
    bvn_mode: str
    bvn_kms_key_id: str | None
    bvn_mac_key_id: str | None
    local_bvn_enc_key: str | None
    local_bvn_mac_key: str | None


def load_settings() -> Settings:
    env = os.environ.get
    return Settings(
        database_url=env("DATABASE_URL"),
        db_host=env("DB_HOST"),
        db_port=int(env("DB_PORT", "5432")),
        db_name=env("DB_NAME", "kestrel"),
        db_secret_arn=env("DB_SECRET_ARN"),
        db_sslmode=env("DB_SSLMODE", "require"),
        db_pool_max=int(env("DB_POOL_MAX", "5")),
        queue_url=env("QUEUE_URL"),
        sqs_endpoint_url=env("SQS_ENDPOINT_URL"),
        notify_topic_arn=env("NOTIFY_TOPIC_ARN"),
        bvn_mode=env("BVN_MODE", "kms"),
        bvn_kms_key_id=env("BVN_KMS_KEY_ID"),
        bvn_mac_key_id=env("BVN_MAC_KEY_ID"),
        local_bvn_enc_key=env("LOCAL_BVN_ENC_KEY"),
        local_bvn_mac_key=env("LOCAL_BVN_MAC_KEY"),
    )
