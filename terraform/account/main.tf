# Account wide controls. Dev and prod share one account (ADR 0001), so there is one trail for both,
# kept outside the per environment stack so destroying dev never removes the audit trail.
module "governance" {
  source      = "../modules/governance"
  name_prefix = "kestrel"
}

# GuardDuty, Security Hub and the AWS Config recorder Security Hub needs (brief item 6.5).
# Account wide, so they live here and not in the per environment stack.
module "security" {
  source      = "../modules/security"
  name_prefix = "kestrel"
}
