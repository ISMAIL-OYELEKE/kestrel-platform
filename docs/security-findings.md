# Security findings (brief item 6.5)

GuardDuty, Security Hub CSPM (AWS Foundational Security Best Practices v1.0.0) and AWS Config were turned on through Terraform on 15 Oct 2026 at 16:58 WAT (`terraform/modules/security`). This is the state of the failed controls about 70 minutes later, taken from the CLI on 15 Oct 2026 at 18:08 WAT (evidence/security-hub-failed-controls.png). There were no CRITICAL findings.

Each control gets one of three outcomes:

- **Fix**: we change Terraform and the control passes.
- **Accept**: we keep the design on purpose; the reason is written here.
- **Out of scope**: the control checks something Kestrel does not use.

## HIGH

| Control | What it checks | Outcome | Why |
|---|---|---|---|
| GuardDuty.7, GuardDuty.11 | GuardDuty EKS and general Runtime Monitoring | Accept | Paid per vCPU add-on. GuardDuty threat detection on CloudTrail, VPC Flow Logs and DNS is on. Runtime Monitoring is a sensible step for the client once the platform carries real customer data |
| Inspector.1 to Inspector.4 | Amazon Inspector scanning of EC2, ECR and Lambda | Accept | Paid per image and per function. ECR basic scanning runs on every push and the pipeline blocks any CRITICAL vulnerability (`scripts/scan-gate.sh`, item 6.6). There is no EC2 at all. Inspector is the upgrade path if the client wants continuous rescans of images already deployed |

## MEDIUM

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
| IAM.3, IAM.8 | Access keys older than 90 days; unused credentials | Pending | Both come from `KommunicateBotUser`, a user from an earlier, unrelated chatbot project. Its access key was created on 26 Jan 2026 and last used on 10 Feb 2026. Kestrel itself uses no access keys (item 6.1) |
| IAM.7 | A strong password policy | Fix | Free. Set an account password policy in the account stack |
| Macie.1 | Amazon Macie is on | Accept | Paid per bucket and per GB scanned. Our buckets hold logs, Config history and build artifacts, not customer files. BVNs never reach S3 (ADR 0007) |
| S3.1 | Account-wide S3 Block Public Access | Fix | Free. Every Kestrel bucket already blocks public access on its own; the account setting makes it the default for any bucket created later |
| SSM.6 | SSM Automation logs to CloudWatch | Out of scope | Kestrel does not use SSM Automation |
