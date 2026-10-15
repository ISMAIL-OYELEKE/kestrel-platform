output "queue_arn" {
  value = aws_sqs_queue.scoring.arn
}

output "queue_url" {
  value = aws_sqs_queue.scoring.id
}

output "queue_name" {
  value = aws_sqs_queue.scoring.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "topic_arn" {
  value = aws_sns_topic.decisions.arn
}
