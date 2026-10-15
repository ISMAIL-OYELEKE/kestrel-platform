resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = var.name
  family = "postgres16"

  # Refuse any connection that is not encrypted with TLS.
  # AWS records this parameter as pending-reboot, so we say the same to avoid a change on every plan.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

# Created here, not by RDS, so it has a retention period and is removed by terraform destroy.
resource "aws_cloudwatch_log_group" "postgresql" {
  #checkov:skip=CKV_AWS_158:Database logs hold errors and connection events, not row data; encrypted at rest by CloudWatch
  name              = "/aws/rds/instance/${var.name}/postgresql"
  retention_in_days = var.log_retention_days
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_161:Brief 5.3 allows Secrets Manager with rotation or IAM auth; we use the RDS managed, rotating secret
  #checkov:skip=CKV_AWS_118:Enhanced monitoring needs an extra role and costs per instance; CloudWatch RDS metrics feed the dashboard and alarms
  #checkov:skip=CKV_AWS_353:Performance Insights is a prod recommendation in the design document; not needed for the assessment workload
  identifier     = var.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  db_name  = "kestrel"
  username = "kestrel_admin"
  # RDS creates the password, stores it in Secrets Manager (encrypted with our key) and rotates it
  # every 7 days. It never appears in code, variables or Terraform state (brief item 5.3).
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Automated backups plus transaction logs uploaded every 5 minutes give point in time restore
  # with a recovery point under 15 minutes (brief item 5.2). Times are UTC: 02:00 to 03:00 in Lagos.
  backup_retention_period = var.backup_retention_days
  backup_window           = "01:00-02:00"
  maintenance_window      = "sun:02:30-sun:03:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-final"
  apply_immediately          = true

  # Database errors and failed logins go to CloudWatch Logs (brief item 8, DB health).
  enabled_cloudwatch_logs_exports = ["postgresql"]
  depends_on                      = [aws_cloudwatch_log_group.postgresql]
}
