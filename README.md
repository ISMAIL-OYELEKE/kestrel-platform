# kestrel-platform

Infrastructure, application and pipeline for the Kestrel Microfinance Bank loan platform on AWS (eu-west-1).

This guide lets a small team deploy everything from an empty AWS account, and remove it again.

## What is in this repository

| Folder | What it holds | Who applies it |
|---|---|---|
| `bootstrap/` | Budget with alerts, Terraform state bucket, GitHub Actions roles | A person, once |
| `terraform/account/` | Account wide audit trail (CloudTrail, encrypted log bucket), GuardDuty, Security Hub and AWS Config | A person, once |
| `terraform/modules/` | Reusable building blocks | Used by the stacks |
| `terraform/platform/` | The one root module for an environment: network, database, API, queue, scorer | A person now, the pipeline later |
| `terraform/envs/` | Only the settings (`terraform.tfvars`) and state location (`backend.hcl`) for dev and prod | |
| `scripts/` | Smoke test, image scan gate and rollback check, used by the pipeline | |
| `.github/workflows/` | CI, Terraform plan on pull requests, deployment with prod approval | GitHub Actions |
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

## Step 2: account audit trail and security services (once per account)

```
cd terraform/account
terraform init
terraform plan -out=account.tfplan
terraform apply account.tfplan
```

Check that `log_admin_arns` in the output is you: only these identities may delete logs. See ADR 0004.

This stack also turns on GuardDuty, Security Hub (AWS Foundational Security Best Practices only) and the AWS Config recorder that Security Hub's checks need. If any of these is already on in your account, import it or remove it from `terraform/modules/security` first, because each can exist only once per account and region. GuardDuty and Security Hub are free for their first 30 days; AWS Config is billed per recorded change, a few dollars a month for this platform.

## Step 3: GitHub settings

In the repository, Settings, Environments, create `dev` and `prod`. For `prod`, limit deployment branches to `main`.

## Step 4: run the application locally

See `app/README.md`. This needs no AWS account.

## Step 5: deploy an environment (dev or prod)

Dev and prod use the same code in `terraform/platform`. Only the files in `terraform/envs/<env>/` differ, so `diff terraform/envs/dev/terraform.tfvars terraform/envs/prod/terraform.tfvars` shows every difference. Replace `dev` with `prod` below for production.

1. Create the image repository first, because the service needs an image to start:
   ```
   cd terraform/platform
   terraform init -backend-config=../envs/dev/backend.hcl
   terraform apply -var-file=../envs/dev/terraform.tfvars -var api_image_tag=none -target=module.api.aws_ecr_repository.api
   ```
2. Build and push the API image, and build the scorer package. Run these from the repository root with a clean `app/` folder; the image is tagged with the git commit:
   ```
   app/push-image.sh dev
   app/build-lambda.sh
   ```
   Note the tag that `push-image.sh` prints.
3. Plan and apply. Check the plan before applying (a new dev environment is about 94 resources). The database takes about 8 minutes:
   ```
   cd terraform/platform
   terraform plan -var-file=../envs/dev/terraform.tfvars -var api_image_tag=<tag> -out=dev.tfplan
   terraform apply dev.tfplan
   ```
4. Prove it works end to end. This checks HTTPS, both scoring decisions, the request ID in the scorer logs, and that no BVN appears in any log:
   ```
   ../../scripts/smoke-aws.sh
   ```

There is no domain yet, so the load balancer uses a self signed certificate. `terraform output -raw certificate_pem` gives the certificate to trust it. See ADR 0008 for what changes when a domain is provided.

## Step 6: the pipeline (GitHub Actions)

After the first manual deployment, changes go through pull requests. See ADR 0009 for the design.

1. In the repository, Settings, Secrets and variables, Actions, Variables, add `DEV_ENABLED` = `true`. Add `PROD_ENABLED` = `true` only when prod should exist. There are no secrets to add: the workflows sign in to AWS with OIDC.
2. Open a pull request. Checks run (lint, tests, Terraform validation, Checkov), and the Terraform plan for dev and prod appears as a comment on the pull request.
3. Merge. The `deploy` workflow deploys dev, then opens an issue titled "Approve prod deployment of ...". Comment `approve` on it to deploy prod, or `deny` to stop.
4. If a new version never becomes healthy, ECS rolls back by itself and the pipeline fails at "Check the new version is running".
5. To see the rollback happen, run the `rollback demo` workflow from the Actions tab (Run workflow, choose the environment). It deploys a deliberately broken image, checks that ECS rolled back to the working version, then redeploys the working version. It takes about 15 minutes.

Checkov findings that were accepted are skipped in the code, next to the resource, with the reason (`#checkov:skip=ID:reason`). The `checkov` job lists them all.

After destroying an environment, set its variable to `false` so the next merge does not rebuild it.

## Removing everything

Remove in the reverse order of creation, so nothing is left behind that still costs money.

1. Destroy dev and prod (each one from `terraform/platform`, after `terraform init -reconfigure -backend-config=../envs/<env>/backend.hcl`):
   ```
   terraform plan -destroy -var-file=../envs/<env>/terraform.tfvars -var api_image_tag=<tag> -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```
   This takes 15 to 25 minutes, mostly waiting for AWS to release the scorer's network interfaces in the VPC.
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

The USD 40 budget sends alerts; it does not stop charges. Spend is controlled by checking cost, keeping tests short and tearing down. Hourly billed resources (the load balancer, Fargate tasks, NAT or VPC endpoints, RDS) exist only in the dev and prod stacks. Destroy dev at the end of each working session. The bootstrap and audit stacks cost under USD 0.10 a day together.

---

## Links

- Case study on my portfolio: https://ismailoyeleke.com/projects/kestrel-loan-platform
- Video walkthrough on YouTube: https://youtu.be/dCuNLgKuf78
- Write-up on Medium: https://medium.com/@ismailoyeleke2003/i-built-a-loan-platform-on-aws-broke-it-on-purpose-and-tore-it-down-for-usd-9-20-e758f948ecd4
- LinkedIn post: https://lnkd.in/p/d_PWxA6Z

---
*Created by [Oyeleke Ismail](https://www.linkedin.com/in/ismail-oyeleke-6930b6317/) - AWS Certified Solutions Architect*
