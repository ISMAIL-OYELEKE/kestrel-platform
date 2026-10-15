# Prod: two tasks across two AZs, standby database in a second AZ, endpoints in both AZs.
environment = "prod"
vpc_cidr    = "10.30.0.0/16"

endpoint_az_count = 2

db_instance_class        = "db.t4g.micro"
db_multi_az              = true
db_backup_retention_days = 7
# Kept off so the assessment can be torn down in one step. A real prod would set this to true.
db_deletion_protection = false
db_skip_final_snapshot = true

api_cpu        = 256
api_memory     = 512
api_min_count  = 2
api_max_count  = 20
waf_rate_limit = 2000

scorer_max_concurrency = 5

log_retention_days = 30
