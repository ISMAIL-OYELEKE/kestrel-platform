# Evidence

Screenshots and command output that prove a brief requirement is met. Each file is listed with the date it was captured and the requirement it supports.

| File | Captured | Shows | Brief item |
|------|----------|-------|------------|
| iam-no-access-keys.png | 15 Oct 2026, 09:37 WAT | IAM user ISMAIL_OYELEKE has 0 access keys and 0 API keys | 6.1 |
| aws-login-short-lived-credentials.png | 15 Oct 2026, 09:44 WAT | `aws login --remote` gives the codespace temporary credentials for IAM user ISMAIL_OYELEKE; no access key used | 6.1 |
| budget-created.png | 15 Oct 2026, 09:51 WAT | Budget kestrel-assessment-usd-40 live before any other resource; October spend so far USD 0.24 (baseline) | Rule: budget first |
| budget-alert-recipient.png | 15 Oct 2026, 09:51 WAT | Alert email is active and subscribed to all 5 budget alerts | Rule: budget first |
| state-bucket-apply.png | 15 Oct 2026, 09:55 WAT | Terraform created the state bucket and its 6 protections (7 resources) | 2.1 |
| state-migrated-to-s3.png | 15 Oct 2026, 09:59 WAT | After migration, plan reads state from S3 and shows no changes; state file present in the bucket | 2.1 |
| github-oidc-roles-apply.png | 15 Oct 2026, 10:07 WAT | Three GitHub OIDC roles created (plan, deploy-dev, deploy-prod); no access keys involved | 6.1, 7.2, 7.3 |
| github-environments.png | 15 Oct 2026, 10:24 WAT | GitHub environments dev and prod created; prod limited to the main branch (Required reviewers is not offered on a free private repo, see 7.3 deviation) | 7.3 |
| cloudtrail-plan.png | 15 Oct 2026, 10:27 WAT | Account stack plan: 10 resources to add; only ISMAIL_OYELEKE is a log admin | 1.2 |
| cloudtrail-apply-and-write-denied.png | 15 Oct 2026, 10:29 WAT | CloudTrail stack applied (10 resources); the admin user is refused s3:PutObject on the log bucket by an explicit deny in the bucket policy | 1.2 |
| cloudtrail-delivering.png | 15 Oct 2026, 10:42 WAT | Trail status: logging on, first log file delivered 09:41 UTC, no delivery error (bucket policy and KMS key policy work) | 1.2 |
| app-local-smoke-test.png | 15 Oct 2026, 10:46 WAT | Local stack: health ok; Ada (3x salary) APPROVED, Bayo (9x) DECLINED; request IDs smoke-ada and smoke-bayo reach the worker; BVN appears 0 times in logs and in no response | A1 to A5, 8.1 |
| dev-platform-plan.png | 15 Oct 2026, 11:10 WAT | Dev platform plan from the single root module with envs/dev/terraform.tfvars: 89 resources to add | 2.2, 3.x, 4.x, 5.x |
| dev-aws-smoke-test.png | 15 Oct 2026, 11:34 WAT | Dev on AWS: HTTP 301 to HTTPS; health ok over HTTPS with the certificate verified; Ada APPROVED and Bayo DECLINED by the scorer Lambda within 2 seconds; the API request ID appears in the Lambda log; BVN appears 0 times in API and scorer logs; invalid BVN gets a 422 that does not echo it | 3.x, 4.1, 4.3, 5.x, 6.x, 8.1 |
| dev-database-and-endpoints.png | 15 Oct 2026, 11:36 WAT | Dev RDS: storage encrypted, not public, PostgreSQL 16.13, password in a Secrets Manager secret with rotation every 7 days; 8 VPC endpoints (S3 gateway plus 7 interface) all available; 0 NAT gateways | 3.x, 5.x, 6.x |
| dev-destroy.png | 15 Oct 2026, 11:51 WAT | Dev platform destroyed at the end of the session: 0 added, 0 changed, 93 destroyed | R5, cost discipline |
| oidc-subject-in-cloudtrail.png | 15 Oct 2026, 16:04 WAT | Why the first pipeline run was refused: CloudTrail shows GitHub's token subject carries permanent IDs (`ISMAIL-OYELEKE@98213704/kestrel-platform@1420375935`), which the role trust did not yet match | 6.1, 7.2 |
| pr-plan-oidc-success.png | 15 Oct 2026, 16:10 WAT | After the trust fix: plan dev and plan prod pass on pull request 1, signing in to AWS through OIDC with no stored keys | 6.1, 7.2 |
