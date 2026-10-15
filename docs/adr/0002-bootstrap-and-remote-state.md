# ADR 0002: Bootstrap stack in Terraform, state in S3 with native locking

Status: Accepted (15 Oct 2026)

## Context
Brief item 2.1 requires all resources in Terraform, with remote state in S3, state locking and encryption. The brief allows the state bucket and OIDC provider to be created by hand if documented. Terraform needs a bucket to store state before it can manage anything, which is a chicken and egg problem.

## Options considered
1. Create the state bucket and OIDC provider by hand in the console, and document it.
2. A small `bootstrap/` Terraform stack that starts with local state, creates the budget, the bucket and the OIDC provider, then moves its own state into the bucket.
3. Locking with a DynamoDB table, or with S3 native lock files (`use_lockfile`, Terraform 1.10 and later).

## Decision
Option 2 with S3 native locking. Nothing is clicked in the console. The bootstrap stack is applied once by a person; every other stack is applied by the pipeline.

## Consequences
- Every AWS resource, including the bucket that holds state, is described in code and can be reviewed and recreated.
- No DynamoDB table to pay for or secure.
- The bucket uses S3 managed encryption (AES-256), versioning, a public access block, an HTTPS only policy and a 30 day expiry for old versions.
- `force_destroy = false`, so final teardown empties the bucket before destroying it. This is a deliberate extra step.
