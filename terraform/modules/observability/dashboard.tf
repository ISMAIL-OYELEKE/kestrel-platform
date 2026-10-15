# One dashboard per environment with what brief item 8.2 asks for: request rate, error rate, p95
# latency, queue depth, dead-letter queue depth and database health, plus the alarms at the top.
data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
  alb_d  = ["LoadBalancer", var.alb_arn_suffix]

  widgets = [
    {
      type = "alarm", x = 0, y = 0, width = 24, height = 3
      properties = {
        title  = "Alarms"
        alarms = [for a in local.alarm_arns : a]
      }
    },
    {
      type = "metric", x = 0, y = 3, width = 8, height = 6
      properties = {
        title   = "API requests per minute"
        region  = local.region, view = "timeSeries", stat = "Sum", period = 60
        metrics = [["AWS/ApplicationELB", "RequestCount", local.alb_d[0], local.alb_d[1], { label = "Requests" }]]
      }
    },
    {
      type = "metric", x = 8, y = 3, width = 8, height = 6
      properties = {
        title  = "API 5xx error rate (%)"
        region = local.region, view = "timeSeries", period = 60
        yAxis  = { left = { min = 0 } }
        metrics = [
          [{ expression = "100 * (FILL(t5, 0) + FILL(e5, 0)) / r", label = "5xx rate %", id = "rate" }],
          ["AWS/ApplicationELB", "RequestCount", local.alb_d[0], local.alb_d[1], { id = "r", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", local.alb_d[0], local.alb_d[1], { id = "t5", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", local.alb_d[0], local.alb_d[1], { id = "e5", stat = "Sum", visible = false }],
        ]
        annotations = { horizontal = [{ value = var.error_rate_percent, label = "alarm" }] }
      }
    },
    {
      type = "metric", x = 16, y = 3, width = 8, height = 6
      properties = {
        title  = "API latency (seconds)"
        region = local.region, view = "timeSeries", period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p95", label = "p95" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p50", label = "p50" }],
        ]
        annotations = { horizontal = [{ value = var.p95_latency_seconds, label = "alarm" }] }
      }
    },
    {
      type = "metric", x = 0, y = 9, width = 8, height = 6
      properties = {
        title  = "Scoring queue"
        region = local.region, view = "timeSeries", stat = "Maximum", period = 60
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.queue_name, { label = "Waiting messages" }],
          ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.queue_name, { label = "Oldest message age (s)", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 9, width = 8, height = 6
      properties = {
        title   = "Dead-letter queue depth"
        region  = local.region, view = "timeSeries", stat = "Maximum", period = 60
        metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name, { label = "Messages in DLQ" }]]
      }
    },
    {
      type = "metric", x = 16, y = 9, width = 8, height = 6
      properties = {
        title  = "Scorer Lambda"
        region = local.region, view = "timeSeries", stat = "Sum", period = 60
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.scorer_function_name],
          ["AWS/Lambda", "Errors", "FunctionName", var.scorer_function_name],
          ["AWS/Lambda", "Duration", "FunctionName", var.scorer_function_name, { stat = "p95", label = "Duration p95 (ms)", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 15, width = 8, height = 6
      properties = {
        title  = "Database health"
        region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier, { label = "CPU %" }],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier, { label = "Connections", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 15, width = 8, height = 6
      properties = {
        title  = "Database free storage (GiB)"
        region = local.region, view = "timeSeries", period = 300
        metrics = [
          [{ expression = "m1 / 1073741824", label = "Free GiB", id = "gib" }],
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_identifier, { id = "m1", stat = "Minimum", visible = false }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 15, width = 8, height = 6
      properties = {
        title  = "API tasks"
        region = local.region, view = "timeSeries", period = 60
        metrics = [
          ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { stat = "Average", label = "Running tasks" }],
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Minimum", label = "Healthy tasks" }],
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { stat = "Average", label = "CPU %", yAxis = "right" }],
        ]
      }
    },
  ]

  alarm_arns = [
    aws_cloudwatch_metric_alarm.api_5xx_rate.arn,
    aws_cloudwatch_metric_alarm.api_p95_latency.arn,
    aws_cloudwatch_metric_alarm.api_no_healthy_tasks.arn,
    aws_cloudwatch_metric_alarm.queue_oldest_message.arn,
    aws_cloudwatch_metric_alarm.dlq_messages.arn,
    aws_cloudwatch_metric_alarm.db_free_storage.arn,
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = local.widgets })
}
