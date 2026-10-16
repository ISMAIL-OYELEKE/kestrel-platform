# ADR 0001: One AWS account for dev and prod, with isolation controls

Status: Accepted, 15 October 2026. Completed 16 October 2026 with the controls as built and run.

## Context
Brief item 1.1 requires separate dev and prod, either as two accounts under AWS Organizations or one account with justified isolation controls. The assessment runs for five days on a USD 40 budget, in the candidate's own account (confirmed by the hiring contact on 15 Oct), and everything is destroyed afterwards.

## Options considered
1. AWS Organizations with a management account plus dev and prod member accounts. The strongest separation: a mistake or a breach in dev cannot reach prod at all, and SCPs (item 1.3) become available. Costs nothing extra, but adds a second set of bootstrap, CloudTrail, GuardDuty, Security Hub and Config per account, and new accounts can take time to be usable.
2. One account, with dev and prod isolated by network, state, keys and IAM. Simpler and cheaper to run for five days, weaker separation.

## Decision
Option 2, one account, for the assessment. Option 1 for the client (see the design document).

## Isolation controls (as built and run on 15 and 16 Oct)
| Layer | Dev | Prod | Where |
|---|---|---|---|
| Network | VPC 10.20.0.0/16 | VPC 10.30.0.0/16 | No peering, no shared subnets. `terraform/envs/*/terraform.tfvars` |
| Terraform state | `platform/dev/terraform.tfstate` | `platform/prod/terraform.tfstate` | Separate files and lock files, `terraform/envs/*/backend.hcl` |
| Encryption keys | `alias/kestrel-dev-*` | `alias/kestrel-prod-*` | Separate customer managed keys per environment, `terraform/modules/kms` |
| Application roles | `kestrel-dev-*` | `kestrel-prod-*` | Each role names only its own environment's queue, topic, keys and secret, and a deny statement blocks its credentials from being used outside its own VPC (`DenyOutsideOurVpc`, `terraform/platform/iam.tf`) |
| Deploy roles | `kestrel-github-deploy-dev` | `kestrel-github-deploy-prod` | Each trusts only a GitHub Actions job running in the matching GitHub environment (OIDC `sub` claim, `bootstrap/github-oidc.tf`) |
| Release gate | Deploys on merge | Deploys only after a human comments "approve" on the gate issue (ADR 0009) | `.github/workflows/deploy.yml` |
| Tags | `Environment = dev` | `Environment = prod` | Provider default tags on every resource (item 10.2) |

## Consequences
- Brief item 1.3 (SCP) is not met, because SCPs need Organizations and never apply to the management account. This is a written deviation, not a silent one.
- **The known gap: both deploy roles have AdministratorAccess on the whole account** (ADR 0003), so a workflow running as the dev deploy role could change prod resources. What contains it: only a job in the `dev` GitHub environment can take that role, credentials last one hour, every call is in CloudTrail, and code reaches the workflow only through a reviewed pull request. In separate accounts this risk does not exist, which is the main reason to move.
- A mistake in an account wide setting (IAM password policy, Security Hub, a service quota) affects both environments. On 16 Oct the shared 12 vCPU Fargate quota showed this: tasks left over from a prod load test blocked a prod deploy (ADR 0010). Dev and prod were never up together for long, so they did not compete, but in a shared account they would.
- For the real client: AWS Organizations with separate dev, prod and log archive accounts, SCPs that block unused regions and stop anyone turning off CloudTrail, and IAM Identity Center for people. The Terraform already supports this: each environment is a variables file and a backend file, so a new account needs only its own bootstrap and backend.
