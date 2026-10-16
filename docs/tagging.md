# Tagging (brief item 10.2)

## The scheme

| Tag | Value | Why |
|---|---|---|
| Environment | `dev`, `prod`, or `shared` for account wide resources (trail, GuardDuty, Security Hub, Config, state bucket, pipeline roles) | Split the bill and the alarms by environment; ADR 0001 uses it as one of the isolation controls |
| Owner | `ismail-oyeleke` | Who to ask before changing or deleting it |
| CostCenter | `kestrel-assessment` | Which budget pays. For the client: the bank's own cost centre code |
| Project | `kestrel` | Separate Kestrel from anything else in the account |
| ManagedBy | `terraform` | A resource without it was made by hand and should be questioned |

## How it is applied

Every stack (`bootstrap`, `terraform/account`, `terraform/platform`) sets all five as provider `default_tags`, so every taggable resource Terraform creates gets them without each resource repeating them. Two places need more than that, because AWS creates the resource, not Terraform:

- ECS tasks: `propagate_tags = "SERVICE"` (`terraform/modules/api/ecs.tf`), so running tasks carry the service's tags.
- Database snapshots: `copy_tags_to_snapshot = true` (`terraform/modules/database/main.tf`).

## How it is enforced

1. **Before anything is created:** the pipeline turns the Terraform plan into JSON and `scripts/check-tags.sh` fails the job if any taggable resource is missing Environment, Owner or CostCenter. It runs on every pull request plan (`terraform-plan.yml`) and before every apply (`deploy-env.yml`).
2. **After, for anything made outside Terraform:** the AWS Config rule `kestrel-required-tags` (managed rule REQUIRED_TAGS, `terraform/modules/security/tags.tf`) marks any supported resource without the three tags as non compliant, and Security Hub shows it.

## Limits

- The Config rule reports; it cannot stop someone creating an untagged resource by hand. Blocking needs AWS Organizations tag policies or an SCP, which a single account does not have (ADR 0001). For the client: a tag policy in Organizations plus an SCP that denies create calls without the tags.
- Resources AWS makes on its own behalf (for example the network interfaces behind interface endpoints, and the account's default VPC) are not tagged by Terraform. Their cost is billed to the parent resource, which is tagged.
- For the tags to appear in Cost Explorer and the bill, they must be activated once as cost allocation tags in the Billing console. That has not been done in this assessment account, which is destroyed after review; it is the first billing step for the client.
