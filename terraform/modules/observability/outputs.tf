output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.api_5xx_rate.alarm_name,
    aws_cloudwatch_metric_alarm.api_p95_latency.alarm_name,
    aws_cloudwatch_metric_alarm.api_no_healthy_tasks.alarm_name,
    aws_cloudwatch_metric_alarm.queue_oldest_message.alarm_name,
    aws_cloudwatch_metric_alarm.dlq_messages.alarm_name,
    aws_cloudwatch_metric_alarm.db_free_storage.alarm_name,
  ]
}
