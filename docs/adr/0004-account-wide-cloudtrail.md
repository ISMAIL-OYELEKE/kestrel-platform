# ADR 0004: One account wide CloudTrail with a tamper resistant log bucket

Status: Accepted, 15 October 2026

## Context

The brief (item 1.2) requires CloudTrail for all regions, delivered to an encrypted S3 bucket that application roles cannot write to or delete from. Dev and prod share one AWS account (ADR 0001), so the usual Organizations controls (an organization trail, an SCP that blocks `cloudtrail:StopLogging`) are not available.

## Decision

1. A separate root stack, `terraform/account`, owns account wide controls. It calls the reusable `terraform/modules/governance` module. It is not part of the per environment stack, so destroying dev or prod never removes the audit trail.
2. One multi region trail with global service events (IAM, STS) and log file validation turned on.
3. Logs are encrypted with a customer managed KMS key with yearly rotation. Only our trail may use it to encrypt.
4. The bucket policy uses explicit denies, which beat any IAM permission, including AdministratorAccess:
   - No IAM user or role may write objects. Only the CloudTrail service can.
   - Only named log admins (by default, the identity that applies this stack) may delete objects or change the bucket policy, lifecycle, versioning or encryption.
   - Plain HTTP is refused.
5. Versioning is on, so an overwritten or deleted log file can be recovered for 30 days.

## Consequences

- Application roles and the CI deploy roles cannot tamper with logs. This stack is therefore applied by the human admin, like the bootstrap, not by CI.
- Cost: the first copy of management events is free. The KMS key is USD 1 per month (charged hourly). S3 storage is a few cents. Estimated under USD 0.05 per day.
- Without an SCP, an admin could still stop the trail. Mitigation: an alarm on `StopLogging` and `DeleteTrail` events is planned in the observability work. The written deviation for item 1.3 is in ADR 0001.
- S3 Object Lock (stretch item 1.4) can be enabled later on this same bucket without recreating it.
