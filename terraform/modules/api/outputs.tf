output "repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.api.arn_suffix
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.api.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "certificate_pem" {
  description = "Public certificate to trust when calling the API (null when a real certificate is used)."
  value       = local.create_certificate ? tls_self_signed_cert.self_signed[0].cert_pem : null
}

output "task_definition_arn" {
  description = "The task definition this apply deployed. The pipeline checks ECS is really running it."
  value       = aws_ecs_task_definition.api.arn
}
