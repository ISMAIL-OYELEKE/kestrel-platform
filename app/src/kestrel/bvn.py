"""Field level protection for the BVN.

Two values are stored instead of the BVN:
- bvn_ciphertext: the BVN encrypted with a KMS key. Only a role with kms:Decrypt can read it back,
  and the API role is not given that permission.
- bvn_lookup_hash: an HMAC of the BVN made with a separate KMS HMAC key. The same BVN always gives
  the same value, so "find applications for this BVN" is an indexed equality query on this column,
  without decrypting anything. Without the key, the hash cannot be reversed or brute forced offline.
"""

import hashlib
import hmac
from typing import Protocol

from .config import Settings


class BvnProtector(Protocol):
    def encrypt(self, bvn: str, application_id: str) -> bytes: ...

    def lookup_hash(self, bvn: str) -> bytes: ...


class KmsBvnProtector:
    def __init__(self, kms_client, enc_key_id: str, mac_key_id: str):
        self._kms = kms_client
        self._enc_key_id = enc_key_id
        self._mac_key_id = mac_key_id

    def encrypt(self, bvn: str, application_id: str) -> bytes:
        # The encryption context binds the ciphertext to its row: copying it onto another row makes
        # decryption fail, and every decrypt is recorded in CloudTrail with this context.
        response = self._kms.encrypt(
            KeyId=self._enc_key_id,
            Plaintext=bvn.encode(),
            EncryptionContext={"purpose": "bvn", "application_id": application_id},
        )
        return response["CiphertextBlob"]

    def lookup_hash(self, bvn: str) -> bytes:
        response = self._kms.generate_mac(KeyId=self._mac_key_id, Message=bvn.encode(), MacAlgorithm="HMAC_SHA_256")
        return response["Mac"]


class LocalBvnProtector:
    """Same behaviour with local keys, for Docker Compose and tests only. Never used in AWS."""

    def __init__(self, enc_key_hex: str, mac_key_hex: str):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        self._aead = AESGCM(bytes.fromhex(enc_key_hex))
        self._mac_key = bytes.fromhex(mac_key_hex)

    def encrypt(self, bvn: str, application_id: str) -> bytes:
        import os

        nonce = os.urandom(12)
        return nonce + self._aead.encrypt(nonce, bvn.encode(), application_id.encode())

    def decrypt(self, blob: bytes, application_id: str) -> str:
        return self._aead.decrypt(blob[:12], blob[12:], application_id.encode()).decode()

    def lookup_hash(self, bvn: str) -> bytes:
        return hmac.new(self._mac_key, bvn.encode(), hashlib.sha256).digest()


def build_protector(settings: Settings) -> BvnProtector:
    if settings.bvn_mode == "kms":
        import boto3

        if not (settings.bvn_kms_key_id and settings.bvn_mac_key_id):
            raise RuntimeError("BVN_KMS_KEY_ID and BVN_MAC_KEY_ID are required when BVN_MODE=kms")
        return KmsBvnProtector(boto3.client("kms"), settings.bvn_kms_key_id, settings.bvn_mac_key_id)
    if settings.bvn_mode == "local":
        if not (settings.local_bvn_enc_key and settings.local_bvn_mac_key):
            raise RuntimeError("LOCAL_BVN_ENC_KEY and LOCAL_BVN_MAC_KEY are required when BVN_MODE=local")
        return LocalBvnProtector(settings.local_bvn_enc_key, settings.local_bvn_mac_key)
    raise RuntimeError(f"Unknown BVN_MODE {settings.bvn_mode!r}")
