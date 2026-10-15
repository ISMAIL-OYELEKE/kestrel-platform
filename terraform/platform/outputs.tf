output "api_url" {
  value = "https://${module.api.alb_dns_name}"
}

output "ecr_repository_url" {
  value = module.api.repository_url
}

output "certificate_pem" {
  description = "Save to a file and use with curl --cacert to call the API with full certificate checks."
  value       = module.api.certificate_pem
}

output "ecs_cluster_name" {
  value = module.api.cluster_name
}

output "ecs_service_name" {
  value = module.api.service_name
}

output "api_log_group" {
  value = module.api.log_group_name
}

output "scorer_function_name" {
  value = module.worker.function_name
}

output "scorer_log_group" {
  value = module.worker.log_group_name
}

output "queue_name" {
  value = module.messaging.queue_name
}

output "dlq_name" {
  value = module.messaging.dlq_name
}

output "decisions_topic_arn" {
  value = module.messaging.topic_arn
}

output "db_identifier" {
  value = module.database.identifier
}
