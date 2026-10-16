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

# 0.5 vCPU: in the dev load test a 0.25 vCPU task reached 100% CPU at about 23 requests a second.
api_cpu       = 512
api_memory    = 1024
api_min_count = 2
api_max_count = 20
# 5 tasks from the 25th to the 28th: 50 requests a second at payday peak, 10 per task (loadtest/README.md).
api_payday_min_count = 5
# Raised from 2000 only for the 25x load test from one machine (loadtest/README.md); put back after.
waf_rate_limit = 30000

scorer_max_concurrency = 5

log_retention_days = 30

alarm_email = "ismailoyeleke2003@gmail.com"
