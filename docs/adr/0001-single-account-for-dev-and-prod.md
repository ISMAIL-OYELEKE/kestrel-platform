# ADR 0001: One AWS account for dev and prod, with isolation controls

Status: Accepted (15 Oct 2026). Draft, to be completed as the controls are built.

## Context
Brief item 1.1 requires separate dev and prod, either as two accounts under AWS Organizations or one account with justified isolation controls. The assessment runs for five days on a USD 40 budget and everything is destroyed afterwards.

## Options considered
1. AWS Organizations with a management account plus dev and prod member accounts.
2. One account, with dev and prod isolated by network, state, keys and IAM.

## Decision
Option 2, one account.

## Isolation controls (to be filled in as built)
- Separate VPC per environment, no peering between them
- Separate Terraform state file per environment
- Separate customer managed KMS keys per environment
- Separate IAM roles per environment; GitHub OIDC deploy roles restricted to the matching GitHub environment
- Environment tag on every resource (10.2)

## Consequences
- Brief item 1.3 (SCP) is not met, because SCPs need Organizations and never apply to the management account. This is a written deviation, not a silent one.
- A mistake in an IAM policy could reach both environments; the controls above reduce, not remove, that risk.
- For the real client, the design document recommends AWS Organizations (separate prod account, SCPs, central log account) before go live.
