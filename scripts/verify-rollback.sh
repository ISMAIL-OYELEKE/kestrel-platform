#!/usr/bin/env bash
# Proves that ECS rolled a broken deployment back by itself (brief item 7.4). Used by the
# rollback demo workflow, run from terraform/platform:
#
#   ../../scripts/verify-rollback.sh <good task definition ARN> <broken task definition ARN> <start epoch>
#
# Passes (exit 0) only when ALL of these are true:
#   - ECS logged, after <start epoch>, that the broken deployment failed and that it rolled back
#   - the primary deployment is the exact good task definition, COMPLETED
#   - every desired task is running
#   - the API answers /health over verified HTTPS
# Anything else fails: the broken version running, an AWS error, or no rollback within 15 minutes.
# A failed AWS call ends the script with an error, so it can never be read as a rollback.
set -euo pipefail
export TZ=UTC # the AWS CLI prints times in local time; UTC keeps the offset +00:00
GOOD=$1
BROKEN=$2
START=$3
[ "$GOOD" != "$BROKEN" ] || { echo "Good and broken task definitions are the same: nothing to prove."; exit 1; }

CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)
echo "Good version:   ${GOOD##*/}"
echo "Broken version: ${BROKEN##*/}"

for _ in $(seq 1 90); do # up to 15 minutes
  SVC=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --output json)
  read -r STATE PRIMARY RUNNING DESIRED < <(jq -r '.services[0] as $s
    | ($s.deployments[] | select(.status == "PRIMARY")) as $p
    | "\($p.rolloutState) \($p.taskDefinition) \($s.runningCount) \($s.desiredCount)"' <<<"$SVC")
  echo "$(date -u +%T) primary: $STATE ${PRIMARY##*/}, running $RUNNING of $DESIRED"

  if [ "$PRIMARY" = "$BROKEN" ] && [ "$STATE" = "COMPLETED" ]; then
    echo "FAIL: the broken version is running. ECS did not roll back."
    exit 1
  fi

  if [ "$PRIMARY" = "$GOOD" ] && [ "$STATE" = "COMPLETED" ] && [ "$RUNNING" = "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
    # Only events from this run count, so an old rollback cannot pass the check.
    EVENTS=$(jq -r --argjson start "$START" '.services[0].events[]
      | select((.createdAt | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) >= $start)
      | .message' <<<"$SVC")
    if ! grep -q "deployment failed" <<<"$EVENTS" || ! grep -q "rolling back to deployment" <<<"$EVENTS"; then
      echo "FAIL: the good version is running, but ECS logged no automatic rollback in this run."
      exit 1
    fi
    grep -E "deployment failed|rolling back to deployment" <<<"$EVENTS"
    CERT=$(mktemp --suffix=.pem)
    terraform output -raw certificate_pem >"$CERT"
    curl -sS --fail --cacert "$CERT" "$(terraform output -raw api_url)/health"
    echo
    echo "PASS: ECS rolled back to ${GOOD##*/} by itself, all $DESIRED tasks are running and the API is healthy."
    exit 0
  fi
  sleep 10
done
echo "FAIL: no automatic rollback to ${GOOD##*/} within 15 minutes."
exit 1
