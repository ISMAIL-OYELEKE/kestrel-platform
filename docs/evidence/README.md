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
