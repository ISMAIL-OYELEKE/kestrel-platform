output "function_name" {
  value = aws_lambda_function.scorer.function_name
}

output "role_arn" {
  value = aws_iam_role.scorer.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.scorer.name
}
