"""Fast tests with no database."""

import json
import logging
from decimal import Decimal

import pytest
from cryptography.exceptions import InvalidTag

from kestrel.logs import JsonFormatter, request_id_var
from kestrel.scoring import decide

from conftest import SAMPLE_BVN


@pytest.mark.parametrize(
    "salary, amount, expected",
    [
        ("100000", "300000", "APPROVED"),  # exactly 3x is allowed ("at most")
        ("100000", "300000.01", "DECLINED"),
        ("100000", "1", "APPROVED"),
        ("50000.50", "151501.51", "DECLINED"),
    ],
)
def test_decision_rule(salary, amount, expected):
    assert decide(Decimal(salary), Decimal(amount)) == expected


def _format(message, **extra):
    record = logging.LogRecord("t", logging.INFO, __file__, 1, message, None, None)
    for key, value in extra.items():
        setattr(record, key, value)
    return JsonFormatter().format(record)


def test_log_lines_are_json_with_request_id():
    token = request_id_var.set("req-123")
    try:
        entry = json.loads(_format("hello", application_id="abc"))
    finally:
        request_id_var.reset(token)
    assert entry["message"] == "hello"
    assert entry["request_id"] == "req-123"
    assert entry["application_id"] == "abc"


def test_anything_shaped_like_a_bvn_is_masked_in_logs():
    line = _format(f"oops {SAMPLE_BVN}", payload={"bvn": SAMPLE_BVN, "nested": [SAMPLE_BVN]})
    assert SAMPLE_BVN not in line
    assert "[REDACTED]" in line


def test_longer_numbers_are_not_masked():
    # A 12 digit number is not a BVN; masking it would hide useful data such as account references.
    assert "123456789012" in _format("ref 123456789012")


def test_local_protector_encrypts_and_binds_to_row(protector):
    blob = protector.encrypt(SAMPLE_BVN, "row-1")
    assert SAMPLE_BVN.encode() not in blob
    assert protector.decrypt(blob, "row-1") == SAMPLE_BVN
    with pytest.raises(InvalidTag):
        protector.decrypt(blob, "row-2")  # ciphertext copied to another row will not decrypt


def test_lookup_hash_is_stable_and_not_the_bvn(protector):
    assert protector.lookup_hash(SAMPLE_BVN) == protector.lookup_hash(SAMPLE_BVN)
    assert protector.lookup_hash(SAMPLE_BVN) != protector.lookup_hash("22123456780")
    assert SAMPLE_BVN.encode() not in protector.lookup_hash(SAMPLE_BVN)
