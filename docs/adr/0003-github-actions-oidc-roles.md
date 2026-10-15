# ADR 0003: GitHub Actions signs in with OIDC; three roles split by trust

Status: Accepted (15 Oct 2026)

## Context
Brief item 6.1 forbids long lived AWS access keys anywhere, including CI/CD. Item 7.2 runs `terraform plan` on pull requests and applies only after merge. Item 7.3 requires a manual approval before prod.

## Options considered
1. Store an IAM user's access keys as GitHub secrets. Forbidden by the brief.
2. GitHub OIDC with one deploy role for everything.
3. GitHub OIDC with separate roles: a read only plan role, and one deploy role per environment, each trusted only from its GitHub environment.

## Decision
Option 3. Roles: `kestrel-github-plan` (ReadOnlyAccess plus the state lock file), `kestrel-github-deploy-dev` and `kestrel-github-deploy-prod` (AdministratorAccess). The trust policy checks the token audience and the exact `sub` claim: pull requests or `main` for plan, `environment:dev` or `environment:prod` for deploy. The prod GitHub environment requires a reviewer.

## Consequences
- No secret is stored in GitHub. Credentials last one hour.
- A pull request, even from a branch, can only plan. It cannot change anything.
- The deploy roles are broad because Terraform creates IAM roles, KMS keys and networking. This is a conscious trade off: the blast radius is limited by who can assume the role, not by what it can do. For the client, the next step is a permissions boundary or a scoped deploy policy built from CloudTrail activity. Brief item 6.2 (least privilege) is applied fully to the application's own ECS task and Lambda roles.
