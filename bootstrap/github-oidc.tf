# Lets GitHub Actions sign in to AWS with short lived OIDC tokens instead of
# stored access keys (brief item 6.1). GitHub proves which repo, branch or
# environment a workflow runs in, and AWS only trusts the exact ones listed here.

# The GitHub OIDC provider already existed in this account before the project
# (an account can hold only one per URL). It is read here, not managed, so the
# final terraform destroy does not remove something other work may rely on.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_host = "token.actions.githubusercontent.com"

  # Which GitHub workflow runs may assume each role. The "sub" claim in GitHub's
  # token names the repo (with its permanent IDs, see variables.tf) plus the pull
  # request, branch or deployment environment.
  role_subjects = {
    # Read only: runs terraform plan on pull requests and on main.
    plan = [
      "repo:${var.github_subject_repo}:pull_request",
      "repo:${var.github_subject_repo}:ref:refs/heads/main",
    ]
    # Applies changes, only from jobs that target the matching GitHub environment.
    # Prod deploys wait for a human approval in the pipeline (brief item 7.3, ADR 0009).
    deploy-dev  = ["repo:${var.github_subject_repo}:environment:dev"]
    deploy-prod = ["repo:${var.github_subject_repo}:environment:prod"]
  }
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.role_subjects

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # The token must be meant for AWS STS.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The token must come from this repo and an allowed trigger.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.role_subjects

  name                 = "kestrel-github-${each.key}"
  description          = "Assumed by GitHub Actions in ${var.github_repo} (${each.key})"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  max_session_duration = 3600 # credentials expire after one hour
}

# Plan role: can read everything, change nothing.
resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.github["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan role also needs to take and release the state lock file during a plan.
data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.github["plan"].id
  policy = data.aws_iam_policy_document.plan_state_lock.json
}

# Deploy roles create every kind of resource, including IAM roles, so they use
# AdministratorAccess. The risk is contained by the trust policy above: only a
# workflow job in the matching GitHub environment can assume them, prod needs a
# human approval, and the credentials last one hour. See ADR 0003.
resource "aws_iam_role_policy_attachment" "deploy_admin" {
  #checkov:skip=CKV_AWS_274:Deploy roles create IAM roles and every other resource type; contained by the OIDC trust policy (environment only), the prod approval step and one hour sessions. See ADR 0003
  for_each = toset(["deploy-dev", "deploy-prod"])

  role       = aws_iam_role.github[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
