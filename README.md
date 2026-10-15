# kestrel-platform

Infrastructure, application and pipeline for the Kestrel Microfinance Bank loan platform on AWS (eu-west-1).

This guide lets a small team deploy everything from an empty AWS account, and remove it again.

## What is in this repository

| Folder | What it holds | Who applies it |
|---|---|---|
| `bootstrap/` | Budget with alerts, Terraform state bucket, GitHub Actions roles | A person, once |
| `terraform/account/` | Account wide audit trail (CloudTrail, encrypted log bucket) | A person, once |
| `terraform/modules/` | Reusable building blocks | Used by the stacks |
| `app/` | Loan API and scorer (Python), Dockerfile, local Docker Compose stack | The pipeline |
| `docs/adr/` | Architecture decision records: why things are built this way | |
| `docs/evidence/` | Screenshots proving each requirement | |

## Before you start

- An AWS account and an IAM user or SSO role with administrator access and MFA. No access keys are needed: sign in with `aws login`.
- A GitHub repository holding this code.
- Tools: Terraform 1.16 or later, AWS CLI v2, Docker. The `.devcontainer/` folder sets all of these up in GitHub Codespaces.

Sign in (this gives short lived credentials from your console session):

```
aws login --remote --region eu-west-1
aws sts get-caller-identity
```

## Step 1: bootstrap (once per account)

The state bucket must exist before Terraform can store state in it. So the bootstrap stack first runs with state on your machine, creates the bucket, then moves its own state into it. See ADR 0002.

1. Edit `bootstrap/variables.tf` if needed (`github_repo`, `owner`), and replace the account number in the bucket name in `bootstrap/backend.tf` and `terraform/account/backend.tf` with yours (the bucket is called `kestrel-tfstate-<account number>`).
2. Move the backend file aside for the first run:
   ```
   cd bootstrap
   mv backend.tf backend.tf.off
   export TF_VAR_alert_email=you@example.com
   terraform init
   terraform apply
   ```
3. Confirm the budget alert email AWS sends you.
4. Move the state into the bucket:
   ```
   mv backend.tf.off backend.tf
   terraform init -migrate-state
   ```
   Answer `yes`. A later `terraform plan` should show no changes.

Created: a USD 40 monthly budget with alerts at 25, 50, 75 and 100 percent, the encrypted and versioned state bucket, and three GitHub Actions roles (plan, deploy-dev, deploy-prod) that use OIDC instead of access keys.

If your account already has the GitHub OIDC provider (`token.actions.githubusercontent.com`), the stack reads it. If it does not, create it once in IAM, Identity providers (audience `sts.amazonaws.com`); see ADR 0003.

## Step 2: account audit trail (once per account)

```
cd terraform/account
terraform init
terraform plan -out=account.tfplan
terraform apply account.tfplan
```

Check that `log_admin_arns` in the output is you: only these identities may delete logs. See ADR 0004.

## Step 3: GitHub settings

In the repository, Settings, Environments, create `dev` and `prod`. For `prod`, limit deployment branches to `main`.

## Step 4: application and environments

Run the application locally first: see `app/README.md`. The dev and prod platform stacks and the pipeline that deploys them are added in the next stage of this project.

## Removing everything

Remove in the reverse order of creation, so nothing is left behind that still costs money.

1. Destroy dev and prod (added in the next stage).
2. Audit trail. The log bucket is emptied automatically:
   ```
   cd terraform/account
   terraform destroy
   ```
   The KMS key waits 7 days before it is deleted. AWS does not charge for a key waiting to be deleted.
3. Bootstrap. Its state lives in the bucket it is about to delete, so move the state back to your machine first:
   ```
   cd bootstrap
   mv backend.tf backend.tf.off
   terraform init -migrate-state
   ```
   The bucket keeps old versions of every file, so empty all versions before destroying:
   ```
   aws s3api delete-objects --bucket kestrel-tfstate-<account number> \
     --delete "$(aws s3api list-object-versions --bucket kestrel-tfstate-<account number> \
     --query '{Objects: [Versions[], DeleteMarkers[]][].{Key: Key, VersionId: VersionId}}' --output json)"
   terraform destroy
   ```
4. In Cost Explorer, check that daily spend has dropped to zero over the next two days.

## Cost

Spend is capped by the USD 40 budget. Hourly billed resources (the load balancer, Fargate tasks, NAT or VPC endpoints, RDS) exist only in the dev and prod stacks. Destroy dev at the end of each working session. The bootstrap and audit stacks cost under USD 0.10 a day together.
