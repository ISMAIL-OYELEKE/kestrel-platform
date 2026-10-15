# Alarms required by brief item 8.3, plus two that would have caught incident tickets 1 and 2 early.
# Every alarm emails the team when it fires and again when it clears, and its description links to
# the runbook section that says what to do (brief item 8.4).

resource "aws_sns_topic" "alarms" {
  #checkov:skip=CKV_AWS_26:Alarm messages carry metric names and values only, never customer data. CloudWatch cannot publish to a topic encrypted with the AWS managed SNS key
  name = "${var.name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alb = { LoadBalancer = var.alb_arn_suffix }
  tg  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
}

# 5xx rate in percent. Errors from our tasks plus errors the load balancer returns itself (503 when
# no task is healthy). Quiet minutes with under 20 requests are ignored, so one failed request at
# night does not page anyone.
resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  alarm_name          = "${var.name}-api-5xx-rate"
  alarm_description   = "More than ${var.error_rate_percent}% of API requests failed with a 5xx error. Runbook: ${var.runbook_url}#api-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_percent
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "rate"
    expression  = "IF(requests >= 20, 100 * (FILL(target5xx, 0) + FILL(elb5xx, 0)) / requests, 0)"
    label       = "5xx error rate (%)"
    return_data = true
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.alb
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id = "target5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.alb
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id = "elb5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = local.alb
      period      = 60
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_p95_latency" {
  alarm_name          = "${var.name}-api-p95-latency"
  alarm_description   = "The slowest 5% of API responses took longer than ${var.p95_latency_seconds}s. Runbook: ${var.runbook_url}#api-p95-latency"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.tg
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.p95_latency_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Any message in the dead-letter queue is an application that was never decided.
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.name}-dlq-messages"
  alarm_description   = "A scoring message failed 3 times and is in the dead-letter queue. Runbook: ${var.runbook_url}#dlq-messages"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "db_free_storage" {
  alarm_name          = "${var.name}-db-free-storage"
  alarm_description   = "The database has less than ${floor(var.free_storage_bytes / 1073741824)} GiB of free disk. Runbook: ${var.runbook_url}#db-free-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = var.free_storage_bytes
  treat_missing_data  = "breaching" # no data from the database is itself a problem
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Ticket 1: no healthy task behind the load balancer means every request gets a 503.
resource "aws_cloudwatch_metric_alarm" "api_no_healthy_tasks" {
  alarm_name          = "${var.name}-api-no-healthy-tasks"
  alarm_description   = "No API task is passing its health check, so the load balancer answers 503. Runbook: ${var.runbook_url}#api-no-healthy-tasks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Ticket 2 and a stuck scorer: applications waiting more than 5 minutes for a decision.
resource "aws_cloudwatch_metric_alarm" "queue_oldest_message" {
  alarm_name          = "${var.name}-queue-oldest-message"
  alarm_description   = "An application has waited more than 5 minutes for a decision. Runbook: ${var.runbook_url}#queue-oldest-message"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = var.queue_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 300
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}
