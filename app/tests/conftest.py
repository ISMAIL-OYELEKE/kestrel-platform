import os

import psycopg
import pytest

from kestrel import db
from kestrel.bvn import LocalBvnProtector
from kestrel.config import Settings

# Fixed test keys. Real deployments use KMS keys; these only exist in tests and Docker Compose.
TEST_ENC_KEY = "00" * 32
TEST_MAC_KEY = "11" * 32
SAMPLE_BVN = "22123456789"


def make_settings(database_url: str) -> Settings:
    return Settings(
        database_url=database_url,
        db_host=None,
        db_port=5432,
        db_name="kestrel",
        db_secret_arn=None,
        db_sslmode="disable",
        db_pool_max=4,
        queue_url="http://queue.local/scoring",
        sqs_endpoint_url=None,
        notify_topic_arn=None,
        bvn_mode="local",
        bvn_kms_key_id=None,
        bvn_mac_key_id=None,
        local_bvn_enc_key=TEST_ENC_KEY,
        local_bvn_mac_key=TEST_MAC_KEY,
    )


@pytest.fixture
def database_url():
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        pytest.skip("TEST_DATABASE_URL not set (start Postgres with docker compose to run database tests)")
    with psycopg.connect(url, autocommit=True) as conn:
        conn.execute("DROP TABLE IF EXISTS applications")
        db.ensure_schema(conn)
    return url


@pytest.fixture
def protector():
    return LocalBvnProtector(TEST_ENC_KEY, TEST_MAC_KEY)


class FakeQueue:
    def __init__(self, fail: bool = False):
        self.fail = fail
        self.sent = []

    def send(self, application_id, request_id):
        if self.fail:
            raise RuntimeError("queue unavailable")
        self.sent.append({"application_id": application_id, "request_id": request_id})


class FakeNotifier:
    def __init__(self, fail_times: int = 0):
        self.fail_times = fail_times
        self.events = []

    def publish(self, event):
        if self.fail_times > 0:
            self.fail_times -= 1
            raise RuntimeError("SNS unavailable")
        self.events.append(event)
