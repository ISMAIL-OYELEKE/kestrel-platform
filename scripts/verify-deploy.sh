#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in --query are JMESPath literals, not shell
# After terraform apply, waits for the ECS deployment to finish and fails if ECS rolled it back
# (brief item 7.4). Run from terraform/platform.
#
# When new tasks keep failing their health checks, the deployment circuit breaker stops the
# deployment and starts a new one with the previous task definition. The service then becomes
# stable again, but on the OLD version, so "stable" alone would hide the failure. This script
# compares the running task definition with the one this apply deployed.
set -euo pipefail
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)
WANT=$(terraform output -raw api_task_definition_arn)
echo "Expecting $WANT"

for _ in $(seq 1 90); do # up to 15 minutes
  read -r STATE RUNNING < <(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].deployments[?status==`PRIMARY`] | [0].[rolloutState, taskDefinition]' --output text)
  echo "$(date -u +%T) primary deployment: $STATE ${RUNNING##*/}"
  if [ "$STATE" = "COMPLETED" ] && [ "$RUNNING" = "$WANT" ]; then
    echo "Deployed: the new version is running."
    exit 0
  fi
  if [ "$STATE" = "FAILED" ] || { [ "$STATE" = "COMPLETED" ] && [ "$RUNNING" != "$WANT" ]; }; then
    echo "ECS rolled back to ${RUNNING##*/}: the new version never became healthy."
    aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
      --query 'services[0].events[:8].[createdAt, message]' --output text
    exit 1
  fi
  sleep 10
done
echo "Timed out waiting for the deployment."
exit 1
