# ADR 0007: Protect the BVN with KMS encryption plus an HMAC lookup hash

Status: Accepted, 15 October 2026

## Context

The BVN (Bank Verification Number, 11 digits) is sensitive personal data under the Nigeria Data Protection Act 2023. The brief says it must never appear in logs, in plain text in the database, or in any API response (item 5.4), and asks how a lookup by BVN would still work. Disk encryption alone is not enough: anyone with database access would read it.

## Options considered

1. **Disk encryption only.** Fails the brief: every database user can read the BVN.
2. **Plain SHA-256 hash for lookups.** There are only 10^11 possible BVNs. A normal laptop can hash all of them in hours, so a plain hash can be reversed.
3. **pgcrypto inside PostgreSQL.** The key would have to be sent to the database, and it would appear in query logs.
4. **KMS encryption for storage, plus a KMS HMAC key for lookups (chosen).**

## Decision

For each application the API stores two values, never the BVN itself:

- `bvn_ciphertext`: the BVN encrypted with a KMS key. The encryption context includes the application ID, so a ciphertext copied to another row will not decrypt, and every decrypt is recorded in CloudTrail.
- `bvn_lookup_hash`: an HMAC-SHA256 of the BVN, computed by KMS with a separate HMAC key that never leaves KMS. The same BVN always gives the same value, and nobody can compute it without permission to call KMS.

**Lookup by BVN:** compute the HMAC of the BVN being searched (`kms:GenerateMac`), then `SELECT ... WHERE bvn_lookup_hash = $1`, using an index. No decryption, no scan.

**Who can do what:**

| Role | Encrypt | Hash | Decrypt |
|---|---|---|---|
| API task | yes (context `purpose = bvn` only) | yes | **no** |
| Scorer | no | no | no |
| Future verification service | | | yes, its own role, audited in CloudTrail |

Responses and logs: the response models have no BVN field; FastAPI's default validation error, which echoes input, is replaced; request bodies are never logged; and the log formatter masks any 11 digit number as a last line of defence.

## Consequences

- A stolen database dump, backup or snapshot exposes no BVNs.
- A compromised API task cannot read stored BVNs, because it has no decrypt permission.
- Each new application makes 2 KMS calls: USD 0.03 per 10,000 calls. At 180,000 applications a month that is about USD 1.
- If the HMAC key were deleted, lookups by BVN would stop working (the encrypted value would still be recoverable). Key deletion has a 7 day waiting period, and deletion is a CloudTrail event that can be alarmed on.
