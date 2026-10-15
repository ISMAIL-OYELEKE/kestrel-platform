# ADR 0006: Reach AWS services through VPC endpoints, with no NAT gateway

Status: Accepted, 15 October 2026

## Context

The API tasks and the scorer run in private subnets with no public IP addresses. They still need to reach AWS services: ECR to pull images, CloudWatch Logs, Secrets Manager, KMS, SQS and SNS. The brief (item 3.3) asks for the outbound strategy to be chosen, costed and defended. Incident ticket 3 shows what happens when this goes wrong: USD 410 a month of NAT data charges, mostly ECR image pulls.

## Options (eu-west-1 prices, October 2026)

| | NAT gateway (one per AZ) | VPC endpoints (chosen) |
|---|---|---|
| Fixed cost, prod (2 AZs) | 2 x USD 0.048/hour = about USD 70/month | 7 interface endpoints x 2 AZs x USD 0.011/hour = about USD 112/month |
| Data cost | USD 0.048 per GB | USD 0.01 per GB |
| S3 and ECR image layers | Free if an S3 gateway endpoint is added | Free through the S3 gateway endpoint |
| Internet access from private subnets | Yes, to anywhere | None. Only the listed AWS services |
| Fixed cost, dev (endpoints in 1 AZ) | USD 0.048/hour | USD 0.077/hour |

## Decision

Use an S3 gateway endpoint (free) and seven interface endpoints: `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, `kms`, `sqs`, `sns`. There is no NAT gateway and no route to the internet from the private or isolated subnets. Dev places the endpoints in one AZ to save money; prod uses both.

## Why, given NAT can be cheaper on fixed cost

1. **Security for a bank.** With no route to the internet, a compromised task cannot send BVNs or other data to an outside server, and cannot download attack tools. Of all the controls in this design, this one would be hardest to add later.
2. **Predictable cost.** Data through endpoints costs about a fifth of NAT data. The cost that hurt in incident 3 grows with traffic; the endpoint cost is mostly fixed.
3. **Cost difference is small at client scale:** about USD 42 a month in prod, under 3 percent of the USD 1,500 budget.

## Consequences

- Any new AWS service the code calls needs its endpoint added here, or the call times out. That is a deliberate checkpoint.
- Calling a third party API on the internet (for example a credit bureau) would need a NAT gateway, or better an egress proxy with an allow list. That is a future decision.
- The endpoint security group allows HTTPS from the whole VPC range. Incident ticket 4 shows tasks failing to start after this rule was tightened, so it is kept simple on purpose.
