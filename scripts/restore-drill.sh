#!/usr/bin/env bash
# Database restore drill (brief items 9.1 and 9.2).
#
# Restores the database to a point in time, points the API and the scorer at the restored copy,
# proves which data came back, then points everything back and deletes the copy. Every step
# writes a UTC timestamp to restore-drill.log so the recovery time can be measured.
#
# Run from terraform/platform with the environment's backend initialised, one step at a time:
#   ../../scripts/restore-drill.sh marker before     # an application that must survive the restore
#   ../../scripts/restore-drill.sh marker after      # one made after the restore point, must be gone
#   ../../scripts/restore-drill.sh restore 2026-10-16T11:20:00Z
#   ../../scripts/restore-drill.sh point             # API and scorer now use the restored copy
#   ../../scripts/restore-drill.sh check             # "before" found, "after" not found
#   ../../scripts/restore-drill.sh back              # API and scorer use the original database again
#   ../../scripts/restore-drill.sh cleanup           # delete the restored copy (before terraform destroy)
#
# The restored copy is created outside Terraform on purpose: in a real incident you restore first
# and bring the code in line afterwards. That is why cleanup must run before terraform destroy.
set -euo pipefail

LOG=restore-drill.log
STATE=.restore-drill
mkdir -p "$STATE"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { echo "$(ts) $*" | tee -a "$LOG"; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

DB=$(terraform output -raw db_identifier)
RESTORED="$DB-restored"
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)
SCORER=$(terraform output -raw scorer_function_name)
URL=$(terraform output -raw api_url)
CERT="$STATE/cert.pem"
terraform output -raw certificate_pem > "$CERT"

# Point the API service and the scorer Lambda at a database host.
use_host() {
  local host=$1 td
  td=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].taskDefinition' --output text)
  [ -f "$STATE/original-task-definition" ] || echo "$td" > "$STATE/original-task-definition"

  # A new revision of the same task definition with only DB_HOST changed.
  aws ecs describe-task-definition --task-definition "$td" --query taskDefinition \
    | HOST="$host" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
for c in d["containerDefinitions"]:
    for e in c.get("environment", []):
        if e["name"] == "DB_HOST":
            e["value"] = os.environ["HOST"]
keep = ["family", "taskRoleArn", "executionRoleArn", "networkMode", "containerDefinitions",
        "requiresCompatibilities", "cpu", "memory", "runtimePlatform"]
print(json.dumps({k: d[k] for k in keep if k in d}))' > "$STATE/task-definition.json"
  td=$(aws ecs register-task-definition --cli-input-json "file://$STATE/task-definition.json" \
    --query 'taskDefinition.taskDefinitionArn' --output text)
  say "registered $td with DB_HOST=$host"
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$td" \
    --query 'service.serviceName' --output text > /dev/null

  # Lambda replaces all environment variables at once, so change one and send them all back.
  aws lambda get-function-configuration --function-name "$SCORER" --query 'Environment' \
    | HOST="$host" python3 -c '
import json, os, sys
env = json.load(sys.stdin)
env["Variables"]["DB_HOST"] = os.environ["HOST"]
print(json.dumps(env))' > "$STATE/scorer-env.json"
  aws lambda update-function-configuration --function-name "$SCORER" \
    --environment "file://$STATE/scorer-env.json" --query 'LastUpdateStatus' --output text > /dev/null
  aws lambda wait function-updated-v2 --function-name "$SCORER"
  say "scorer Lambda now uses DB_HOST=$host"

  say "waiting for the API service to be stable on the new task definition"
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
  say "API service stable"
}

get_status() { curl -sS -o /dev/null -w '%{http_code}' --cacert "$CERT" "$URL/applications/$1"; }

case "${1:-}" in
  marker)
    name=${2:?say before or after}
    id=$(curl -sS --fail-with-body --cacert "$CERT" -X POST "$URL/applications" \
      -H 'content-type: application/json' -H "X-Request-ID: restore-drill-$name" \
      -d "{\"applicant_name\":\"Restore drill $name\",\"bvn\":\"99000000001\",\"monthly_salary\":100000,\"requested_amount\":100000}" \
      | json 'd["id"]')
    echo "$id" > "$STATE/marker-$name"
    say "marker '$name' created: application $id"
    ;;
  restore)
    point=${2:?give the restore time in UTC, for example 2026-10-16T11:20:00Z}
    latest=$(aws rds describe-db-instances --db-instance-identifier "$DB" \
      --query 'DBInstances[0].LatestRestorableTime' --output text)
    say "restore requested: $DB to $point (latest restorable time now $latest)"
    src=$(aws rds describe-db-instances --db-instance-identifier "$DB" --query 'DBInstances[0]')
    subnets=$(echo "$src" | json 'd["DBSubnetGroup"]["DBSubnetGroupName"]')
    sg=$(echo "$src" | json 'd["VpcSecurityGroups"][0]["VpcSecurityGroupId"]')
    params=$(echo "$src" | json 'd["DBParameterGroups"][0]["DBParameterGroupName"]')
    # Single AZ is enough to prove the restore; a real recovery would match the source (Multi-AZ).
    aws rds restore-db-instance-to-point-in-time \
      --source-db-instance-identifier "$DB" --target-db-instance-identifier "$RESTORED" \
      --restore-time "$point" --db-instance-class db.t4g.micro --no-multi-az \
      --db-subnet-group-name "$subnets" --vpc-security-group-ids "$sg" \
      --db-parameter-group-name "$params" --no-publicly-accessible --no-deletion-protection \
      --tags Key=Project,Value=kestrel Key=Environment,Value=prod Key=Owner,Value=ismail-oyeleke \
             Key=CostCenter,Value=kestrel-assessment Key=ManagedBy,Value=restore-drill \
      --query 'DBInstance.DBInstanceStatus' --output text
    say "waiting for $RESTORED to become available"
    aws rds wait db-instance-available --db-instance-identifier "$RESTORED"
    say "$RESTORED available"
    ;;
  point)
    host=$(aws rds describe-db-instances --db-instance-identifier "$RESTORED" \
      --query 'DBInstances[0].Endpoint.Address' --output text)
    say "pointing the application at $host"
    use_host "$host"
    ;;
  check)
    for name in before after; do
      say "marker '$name' application $(cat "$STATE/marker-$name"): HTTP $(get_status "$(cat "$STATE/marker-$name")")"
    done
    ;;
  back)
    host=$(aws rds describe-db-instances --db-instance-identifier "$DB" \
      --query 'DBInstances[0].Endpoint.Address' --output text)
    say "pointing the application back at $host"
    # Reuse the task definition Terraform deployed, so nothing drifts from the code.
    aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
      --task-definition "$(cat "$STATE/original-task-definition")" --query 'service.serviceName' --output text > /dev/null
    aws lambda get-function-configuration --function-name "$SCORER" --query 'Environment' \
      | HOST="$host" python3 -c '
import json, os, sys
env = json.load(sys.stdin)
env["Variables"]["DB_HOST"] = os.environ["HOST"]
print(json.dumps(env))' > "$STATE/scorer-env.json"
    aws lambda update-function-configuration --function-name "$SCORER" \
      --environment "file://$STATE/scorer-env.json" --query 'LastUpdateStatus' --output text > /dev/null
    aws lambda wait function-updated-v2 --function-name "$SCORER"
    aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
    say "back on $host"
    ;;
  cleanup)
    say "deleting $RESTORED"
    aws rds delete-db-instance --db-instance-identifier "$RESTORED" --skip-final-snapshot \
      --delete-automated-backups --query 'DBInstance.DBInstanceStatus' --output text
    aws rds wait db-instance-deleted --db-instance-identifier "$RESTORED"
    say "$RESTORED deleted"
    ;;
  *)
    sed -n '2,20p' "$0"; exit 1 ;;
esac
