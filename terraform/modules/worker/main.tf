resource "aws_cloudwatch_log_group" "scorer" {
  # Lambda writes to this exact name, so creating it here lets Terraform set retention and delete it.
  name              = "/aws/lambda/${var.name}-scorer"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# The scorer's own role (brief item 6.2).
resource "aws_iam_role" "scorer" {
  name               = "${var.name}-scorer"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# AWS managed policy for a Lambda in a VPC: write logs, and create the network interfaces it uses
# to join the private subnets.
resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.scorer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "scorer" {
  name   = "scorer-permissions"
  role   = aws_iam_role.scorer.id
  policy = var.policy_json
}

resource "aws_lambda_function" "scorer" {
  function_name    = "${var.name}-scorer"
  role             = aws_iam_role.scorer.arn
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  handler          = "kestrel.scorer.handler"
  filename         = var.zip_path
  source_code_hash = filebase64sha256(var.zip_path)
  timeout          = var.timeout_seconds
  memory_size      = var.memory_mb

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.scorer, aws_iam_role_policy_attachment.vpc_access]
}

resource "aws_lambda_event_source_mapping" "queue" {
  event_source_arn = var.queue_arn
  function_name    = aws_lambda_function.scorer.arn
  batch_size       = 10
  # Only the failed messages in a batch are retried, not the whole batch.
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.max_concurrency
  }
}
