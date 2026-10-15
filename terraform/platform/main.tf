# The one root module for every environment. It only wires modules together; dev and prod run this
# same code with a different variables file.

locals {
  name            = "kestrel-${var.environment}"
  app_port        = 8000
  scorer_timeout  = 30
  scorer_zip_path = coalesce(var.scorer_zip_path, "${path.module}/../../app/dist/scorer.zip")
}

module "network" {
  source                  = "../modules/network"
  name                    = local.name
  cidr                    = var.vpc_cidr
  az_count                = 2
  endpoint_az_count       = var.endpoint_az_count
  app_port                = local.app_port
  flow_log_retention_days = var.log_retention_days
}

module "kms" {
  source = "../modules/kms"
  name   = local.name
}

module "database" {
  source                = "../modules/database"
  name                  = local.name
  subnet_ids            = module.network.isolated_subnet_ids
  security_group_id     = module.network.security_group_ids.db
  kms_key_arn           = module.kms.data_key_arn
  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  log_retention_days    = var.log_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}

module "messaging" {
  source = "../modules/messaging"
  name   = local.name
  # AWS guidance: at least 6 times the function timeout, so a slow invocation is never handed to a
  # second worker while still running (the cause in incident ticket 2).
  visibility_timeout_seconds = 6 * local.scorer_timeout
}

module "api" {
  source                = "../modules/api"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.security_group_ids.alb
  app_security_group_id = module.network.security_group_ids.app
  app_port              = local.app_port
  image_tag             = var.api_image_tag
  cpu                   = var.api_cpu
  memory                = var.api_memory
  min_count             = var.api_min_count
  max_count             = var.api_max_count
  waf_rate_limit        = var.waf_rate_limit
  certificate_arn       = var.certificate_arn
  log_retention_days    = var.log_retention_days
  task_policy_json      = data.aws_iam_policy_document.api.json

  environment_variables = {
    AWS_DEFAULT_REGION = var.region
    DB_HOST            = module.database.address
    DB_PORT            = tostring(module.database.port)
    DB_NAME            = module.database.db_name
    DB_SECRET_ARN      = module.database.secret_arn
    DB_SSLMODE         = "require"
    DB_POOL_MAX        = "5"
    QUEUE_URL          = module.messaging.queue_url
    BVN_MODE           = "kms"
    BVN_KMS_KEY_ID     = module.kms.bvn_encrypt_key_arn
    BVN_MAC_KEY_ID     = module.kms.bvn_mac_key_arn
  }
}

module "worker" {
  source             = "../modules/worker"
  name               = local.name
  zip_path           = local.scorer_zip_path
  subnet_ids         = module.network.private_subnet_ids
  security_group_id  = module.network.security_group_ids.worker
  queue_arn          = module.messaging.queue_arn
  timeout_seconds    = local.scorer_timeout
  max_concurrency    = var.scorer_max_concurrency
  log_retention_days = var.log_retention_days
  policy_json        = data.aws_iam_policy_document.worker.json

  environment_variables = {
    DB_HOST          = module.database.address
    DB_PORT          = tostring(module.database.port)
    DB_NAME          = module.database.db_name
    DB_SECRET_ARN    = module.database.secret_arn
    DB_SSLMODE       = "require"
    NOTIFY_TOPIC_ARN = module.messaging.topic_arn
  }
}

module "observability" {
  source                  = "../modules/observability"
  name                    = local.name
  alarm_email             = var.alarm_email
  runbook_url             = "https://github.com/ISMAIL-OYELEKE/kestrel-platform/blob/main/docs/runbook.md"
  alb_arn_suffix          = module.api.alb_arn_suffix
  target_group_arn_suffix = module.api.target_group_arn_suffix
  ecs_cluster_name        = module.api.cluster_name
  ecs_service_name        = module.api.service_name
  queue_name              = module.messaging.queue_name
  dlq_name                = module.messaging.dlq_name
  scorer_function_name    = module.worker.function_name
  db_identifier           = module.database.identifier
}
