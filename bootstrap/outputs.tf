output "budget_name" {
  description = "Name of the cost budget, to find it in the Billing console."
  value       = aws_budgets_budget.assessment.name
}

output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state for all stacks."
  value       = aws_s3_bucket.tfstate.bucket
}
