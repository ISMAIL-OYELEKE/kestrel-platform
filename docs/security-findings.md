# Security findings (brief item 6.5)

GuardDuty, Security Hub CSPM (AWS Foundational Security Best Practices v1.0.0) and AWS Config were turned on through Terraform on 15 Oct 2026 at 16:58 WAT (`terraform/modules/security`). This is the state of the failed controls about 70 minutes later, taken from the CLI on 15 Oct 2026 at 18:08 WAT (evidence/security-hub-failed-controls.png). There were no CRITICAL findings.

Each control gets one of three outcomes:

- **Fix**: we change Terraform and the control passes.
- **Accept**: we keep the design on purpose; the reason is written here.
- **Out of scope**: the control checks something Kestrel does not use.

## GuardDuty

GuardDuty had **no findings** on 15 Oct 2026 at 18:17 WAT, about 80 minutes after it was turned on (evidence/guardduty-findings-none.png, evidence/guardduty-summary.png): 0 attack sequences, 0 Critical, 0 High, 0 Medium. That is expected for a new, quiet account. The k6 load test from a single Codespace address at 17:45 WAT did not raise a finding, because a burst of HTTPS requests to our own load balancer is not a GuardDuty threat pattern; the WAF rate rule is what guards against that.

If GuardDuty raises a finding later, the first step is the same as any alarm: open the finding, note the resource and the time, and follow the leaked credentials playbook in docs/incidents.md (ticket 5) when an IAM principal is involved.

## Security Hub: HIGH

| Control | What it checks | Outcome | Why |
|---|---|---|---|
| GuardDuty.7, GuardDuty.11 | GuardDuty EKS and general Runtime Monitoring | Accept | Paid per vCPU add-on. GuardDuty threat detection on CloudTrail, VPC Flow Logs and DNS is on. Runtime Monitoring is a sensible step for the client once the platform carries real customer data |
| Inspector.1 to Inspector.4 | Amazon Inspector scanning of EC2, ECR and Lambda | Accept | Paid per image and per function. ECR basic scanning runs on every push and the pipeline blocks any CRITICAL vulnerability (`scripts/scan-gate.sh`, item 6.6). There is no EC2 at all. Inspector is the upgrade path if the client wants continuous rescans of images already deployed |

## Security Hub: MEDIUM

| Control | What it checks | Outcome | Why |
|---|---|---|---|
| Account.1 | A security contact on the account | Fix | Free. Set the security alternate contact in the account stack |
| CloudTrail.5 | CloudTrail also sends events to CloudWatch Logs | Accept | The trail already delivers to an encrypted S3 bucket that application roles cannot write to or delete (item 1.2). Sending a copy to CloudWatch Logs adds ingestion cost for alerting we do not use yet |
| EC2.6 | VPC Flow Logs in every VPC | Out of scope | Our VPCs have Flow Logs (item 3.4). The failing VPC is the account's default VPC, which Kestrel never uses |
| EC2.7 | EBS volumes encrypted by default | Fix | Free account setting. Kestrel has no EBS volumes (Fargate and RDS), but it protects anything created later |
| EC2.10, EC2.55 to EC2.58, EC2.60 | Interface endpoints for EC2, ECR, Systems Manager and Incident Manager | Accept | Each interface endpoint costs USD 0.011 an hour per AZ, about USD 8 a month. We create only the endpoints the platform calls (ADR 0006). Kestrel never calls the EC2, Systems Manager or Incident Manager APIs. The ECR results (EC2.55, EC2.56) are for the default VPC, because our VPCs already have the ECR endpoints |
| EC2.172 | VPC Block Public Access blocks internet gateway traffic | Accept | The load balancer has to receive traffic from the internet through the internet gateway. The application and database subnets have no route to it |
| ECS.20 | Task definitions name a non-root user | Fix | The image already runs as user 10001 (`app/Dockerfile`), but the control reads the task definition, so we set `user` there too |
| ELB.17 | HTTPS listener uses a recommended TLS policy | Under review | The listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.2 and 1.3 only). We will check which policy the control expects and switch if it is stricter |
| ELB.18 | Load balancer listeners use secure protocols | Accept | The only non-HTTPS listener is port 80, and it does nothing but send a 301 redirect to HTTPS (ADR 0008). Removing it would make customers who type http:// get a timeout instead |
| ELB.21, ELB.22 | Target groups use HTTPS to the tasks and for health checks | Accept | TLS ends at the load balancer. Traffic to the tasks stays inside private subnets, and security groups allow it only from the load balancer (ADR 0008). Re-encrypting would mean certificates inside every task for little gain |
| GuardDuty.12, GuardDuty.13 | GuardDuty ECS and EC2 Runtime Monitoring | Accept | Same as GuardDuty.11 above |
| IAM.3, IAM.8 | Access keys older than 90 days; unused credentials | Fixed | Both came from `KommunicateBotUser`, a user left over from an earlier, unrelated chatbot project. Its access key was created on 26 Jan 2026 and last used on 10 Feb 2026. Ismail confirmed nothing uses it, so on 15 Oct 2026 at 18:15 WAT the key was deleted, its two AWS managed Lex policies detached and the user deleted (evidence/iam-unused-user-deleted.png). The account now has one IAM user, with no access keys (item 6.1) |
| IAM.7 | A strong password policy | Fix | Free. Set an account password policy in the account stack |
| Macie.1 | Amazon Macie is on | Accept | Paid per bucket and per GB scanned. Our buckets hold logs, Config history and build artifacts, not customer files. BVNs never reach S3 (ADR 0007) |
| S3.1 | Account-wide S3 Block Public Access | Fix | Free. Every Kestrel bucket already blocks public access on its own; the account setting makes it the default for any bucket created later |
| SSM.6 | SSM Automation logs to CloudWatch | Out of scope | Kestrel does not use SSM Automation |

## Recheck with prod running (16 Oct 2026)

Security Hub score at 12:42 WAT: **90%**, 285 controls passed and 33 failed (evidence/prod-securityhub-fsbp-score.png). GuardDuty at 12:45 WAT: 2 findings, 0 critical, 0 high, 0 attack sequences (evidence/prod-guardduty-summary.png).

The recheck showed that the five "Fix" items above had not been made: EC2.7, ECS.20, IAM.7 and S3.1 were still failing (Account.1 now passes). That was our miss. They are now in Terraform, with the new findings below that are free to close:

| Control | Severity | Resource | Outcome | Change |
|---|---|---|---|---|
| EC2.7 | MEDIUM | Account | Fix | `aws_ebs_encryption_by_default` in `terraform/modules/security/baseline.tf` |
| S3.1 | MEDIUM | Account | Fix | `aws_s3_account_public_access_block`, same file |
| IAM.7 | MEDIUM | Account | Fix | `aws_iam_account_password_policy`: 14 characters, all four character types, last 24 passwords blocked. No forced expiry: NIST SP 800-63B advises against periodic rotation, and MFA is on |
| SSM.7 | CRITICAL | Account | Fix | `aws_ssm_service_setting` turns off public sharing of Systems Manager documents. Kestrel has none, so the risk was theoretical, but it is free |
| ECS.20 | MEDIUM | API task definition | Fix | `user = "10001"` in the container definition. The image already ran as that user; now the task definition says so too |
| S3.5 | MEDIUM | kestrel-prod-artifacts bucket | Fix | Bucket policy that denies any request without TLS (`terraform/modules/worker/main.tf`) |
| S3.13 | LOW | kestrel-prod-artifacts bucket | Fix | Lifecycle rule that removes unfinished uploads after 7 days |

The rest are accepted or out of scope, with the reason:

| Control | Severity | Outcome | Why |
|---|---|---|---|
| KMS.3 (6 keys) | CRITICAL | Accept | These are the dev environment's keys, scheduled for deletion by `terraform destroy` on 15 Oct. The control warns that a key is about to be deleted; here that is exactly what we want. The 7 day waiting period (`deletion_window_in_days`) is the safety net the control is asking for |
| IAM.6 | CRITICAL | Accept | Asks for a physical MFA key on the root user. Root has app based (virtual) MFA and is never used day to day. A hardware key is the right step for the client's production account |
| IAM.2 | LOW | Accept | The one IAM user (ISMAIL_OYELEKE) has AdministratorAccess attached directly. For a one person account that is the simplest safe option. For a team: IAM Identity Center with permission sets, so nobody has a long lived IAM user at all |
| ELB.5 | MEDIUM | Accept | Load balancer access logs cost S3 storage and are not needed while WAF logs and application logs (with request IDs) already show every request. Turn on for the client |
| ELB.6 | MEDIUM | Accept | Deletion protection would block our end of day `terraform destroy`. Turn on in the client's production |
| ELB.17 | MEDIUM | Under review | Fails on the HTTPS listener although it uses `ELBSecurityPolicy-TLS13-1-2-2021-06`. We will compare against the policy list in the control's finding detail before changing it |
| S3.9 (4 buckets) | MEDIUM | Accept | Server access logs for log, Config and artifacts buckets mostly log the log writers. CloudTrail already records who changed what |
| GuardDuty.7, .11, .12, .13; Inspector.1 to .4; Macie.1; SSM.6; ELB.18, .21, .22 | | Accept | As in the first review above |
