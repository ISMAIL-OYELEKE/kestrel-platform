# Account wide controls. Dev and prod share one account (ADR 0001), so there is one trail for both,
# kept outside the per environment stack so destroying dev never removes the audit trail.
module "governance" {
  source      = "../modules/governance"
  name_prefix = "kestrel"
}
