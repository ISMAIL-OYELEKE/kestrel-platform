# ADR 0009: Pipeline design, and a prod approval step without GitHub's Required reviewers

Status: Accepted, 15 October 2026

## Context

The brief asks for a GitHub Actions pipeline that lints, tests, builds, scans, pushes and deploys (7.1), posts `terraform plan` on pull requests and applies only after merge (7.2), needs a manual approval before prod (7.3), and rolls back a failed deployment automatically (7.4). It must use OIDC, never stored AWS keys (6.1).

The usual way to gate prod is a GitHub environment with **Required reviewers**. That setting is not available for private repositories on the GitHub Free plan: the prod environment settings page does not offer it (checked 15 October 2026, screenshot `github-environments.png`). The repository must stay private (deliverable DL1).

## Options considered for the prod approval

1. **Make the repository public** to unlock Required reviewers. Rejected: the brief asks for a private repository.
2. **Upgrade to GitHub Pro** (about USD 4 a month). Would work, but spends money and depends on a personal plan the client's team may not share.
3. **Manual `workflow_dispatch` for prod only.** A person starts the prod deployment by hand. Simple, but nothing ties the prod deployment to the exact commit that passed in dev, and anyone with write access can start it.
4. **An approval step inside the workflow that opens a GitHub issue and waits (chosen).** The `trstringer/manual-approval` action creates an issue naming the commit and the workflow run, and waits until a listed approver comments "approve" or "deny".

## Decision

Four workflows in `.github/workflows/`:

| Workflow | When | What it does | AWS role |
|---|---|---|---|
| `ci.yml` | Every pull request, and first step of every deployment | Ruff lint, unit and database tests (real PostgreSQL), `terraform fmt` and `validate` on every stack, Checkov scan | None |
| `terraform-plan.yml` | Every pull request | `terraform plan` for dev and prod, posted as a comment on the pull request and updated on each push | `kestrel-github-plan` (read only) |
| `deploy.yml` | Push to `main` (after merge) | Runs `ci.yml`, deploys dev, waits for approval, deploys prod | (see below) |
| `deploy-env.yml` | Called by `deploy.yml` | Build the scorer package, create the image repository if new, build and push the image, ECR scan gate (fails on any CRITICAL finding), plan and apply, check ECS did not roll back, smoke test | `kestrel-github-deploy-<env>`, only from a job in that GitHub environment |

The prod approval is option 4. The approver list is in `deploy.yml` (`approvers: ISMAIL-OYELEKE`); the client adds their own GitHub usernames there. Prod still runs in the `prod` GitHub environment, which only accepts deployments from `main`, and only a job in that environment can assume the prod AWS role.

Two repository variables, `DEV_ENABLED` and `PROD_ENABLED`, switch each environment's deployment on. Without them a documentation push could rebuild an environment we destroyed to save money.

**Rollback (7.4).** The ECS deployment circuit breaker rolls back by itself when new tasks never become healthy. After a rollback the service is stable again, but on the old version, so a pipeline that only waits for "stable" would report success. `scripts/verify-deploy.sh` compares the task definition ECS is running with the one Terraform just deployed, and fails the pipeline if they differ.

## Consequences

- An approval is a comment on an issue, so it is recorded with the approver's name and time, and the issue links to the exact workflow run and commit.
- The approval step needs `issues: write` for that one job. No other job can write issues.
- The approval waits at most 60 minutes, then the run fails and nothing reaches prod.
- If the client moves to GitHub Team or Enterprise, Required reviewers on the `prod` environment can replace the issue step: delete the `approve-prod` job and add reviewers in the environment settings.
- After a rollback, Terraform state records the new (broken) task definition while ECS runs the old one. The next successful deployment brings them back in line; the runbook covers it.
- Actions are pinned to major version tags (for example `actions/checkout@v4`). Pinning to full commit SHAs is stronger and is listed as a follow-up for the client.
