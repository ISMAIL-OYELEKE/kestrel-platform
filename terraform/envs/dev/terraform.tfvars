# Dev: smallest sizes, one AZ for the endpoints, no standby database. Destroyed after every session.
environment = "dev"
vpc_cidr    = "10.20.0.0/16"

endpoint_az_count = 1

db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 1
db_deletion_protection   = false
db_skip_final_snapshot   = true

api_cpu        = 256
api_memory     = 512
api_min_count  = 1
api_max_count  = 3
waf_rate_limit = 2000

scorer_max_concurrency = 2

log_retention_days = 7
