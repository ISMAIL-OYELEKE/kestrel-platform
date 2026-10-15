output "budget_name" {
  description = "Name of the cost budget, to find it in the Billing console."
  value       = aws_budgets_budget.assessment.name
}
