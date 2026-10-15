# Least privilege (brief item 6.2): each role lists the exact actions on the exact resources its code
# uses. No "*" actions, and no "*" resources on KMS, Secrets Manager, SQS or SNS.

data "aws_region" "current" {}

locals {
  secrets_manager_service = "secretsmanager.${data.aws_region.current.region}.amazonaws.com"
}

data "aws_iam_policy_document" "read_db_secret" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.database.secret_arn]
  }

  # The secret is encrypted with our data key. Decrypt is allowed only when Secrets Manager asks on
  # our behalf, so this role cannot use the key directly on anything else (for example backups).
  statement {
    sid       = "DecryptDatabaseSecret"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.data_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.secrets_manager_service]
    }
  }
}

data "aws_iam_policy_document" "api" {
  source_policy_documents = [data.aws_iam_policy_document.read_db_secret.json]

  # Encrypt only. The API has no permission to decrypt a BVN, so even a compromised API task cannot
  # read stored BVNs back. The context condition matches what the code sends.
  statement {
    sid       = "EncryptBvn"
    actions   = ["kms:Encrypt"]
    resources = [module.kms.bvn_encrypt_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:purpose"
      values   = ["bvn"]
    }
  }

  statement {
    sid       = "HashBvnForLookup"
    actions   = ["kms:GenerateMac"]
    resources = [module.kms.bvn_mac_key_arn]
  }

  statement {
    sid       = "QueueScoringJobs"
    actions   = ["sqs:SendMessage"]
    resources = [module.messaging.queue_arn]
  }
}

data "aws_iam_policy_document" "worker" {
  source_policy_documents = [data.aws_iam_policy_document.read_db_secret.json]

  # What the Lambda event source mapping needs to read and remove messages for this function.
  statement {
    sid = "ConsumeScoringJobs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [module.messaging.queue_arn]
  }

  statement {
    sid       = "PublishDecisions"
    actions   = ["sns:Publish"]
    resources = [module.messaging.topic_arn]
  }
}
