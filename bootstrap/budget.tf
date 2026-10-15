# The first AWS resource of the project: a cost budget that emails an alert
# at USD 10, 20, 30 and 40 of real spend, before anything else is deployed (brief rule).
resource "aws_budgets_budget" "assessment" {
  name         = "kestrel-assessment-usd-${var.budget_limit_usd}"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Count real usage only. Credits and refunds would hide the true spend,
  # and the brief's limit is about what the platform actually costs.
  cost_types {
    include_credit = false
    include_refund = false
  }

  # One email alert per quarter of the budget: 25% = $10, 50% = $20, 75% = $30, 100% = $40.
  dynamic "notification" {
    for_each = [25, 50, 75, 100]
    content {
      notification_type          = "ACTUAL"
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  # Early warning: AWS predicts the month will end above the full budget.
  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }
}
