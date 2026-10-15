# Messages that fail max_receive_count times land here for a person to inspect. Any message here
# raises an alarm (Saturday's observability work).
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-scoring-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum, to give time to investigate
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "scoring" {
  name                       = "${var.name}-scoring"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Only the scoring queue may send its failures to this DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.scoring.arn]
  })
}

# Every decision is published here. Other systems (SMS, CRM, reporting) subscribe without any change
# to our code (brief item 4.5).
resource "aws_sns_topic" "decisions" {
  name              = "${var.name}-loan-decisions"
  kms_master_key_id = "alias/aws/sns"
}
