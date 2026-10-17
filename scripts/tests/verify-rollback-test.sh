#!/usr/bin/env bash
# Local tests for verify-rollback.sh with stub aws, terraform, curl and sleep commands, so no AWS
# access is needed. Each case checks that the script passes only on a real automatic rollback.
# Run from the repo root: scripts/tests/verify-rollback-test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

GOOD=arn:aws:ecs:eu-west-1:111111111111:task-definition/kestrel-dev-api:5
BROKEN=arn:aws:ecs:eu-west-1:111111111111:task-definition/kestrel-dev-api:6
START=1760545000 # 2025-10-15T16:16:40Z; events below are before or after it

cat >"$WORK/bin/terraform" <<'STUB'
#!/usr/bin/env bash
case "$3" in
  ecs_cluster_name) echo kestrel-dev ;;
  ecs_service_name) echo api ;;
  certificate_pem) echo "-----BEGIN CERTIFICATE-----" ;;
  api_url) echo https://example.test ;;
esac
STUB
cat >"$WORK/bin/aws" <<'STUB'
#!/usr/bin/env bash
[ "${AWS_EXIT:-0}" = 0 ] || { echo "An error occurred (AccessDeniedException)" >&2; exit "$AWS_EXIT"; }
cat "$FIXTURE"
STUB
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
[ "${CURL_EXIT:-0}" = 0 ] || exit "$CURL_EXIT"
echo '{"status":"ok"}'
STUB
printf '#!/usr/bin/env bash\n' >"$WORK/bin/sleep"
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"

# fixture <primary task definition> <rollout state> <running> <desired> <event time> [events: yes|no]
fixture() {
  local events='[]'
  if [ "${6:-yes}" = yes ]; then
    events='[
      {"createdAt": "'"$5"'.126000+00:00", "message": "(service api) has reached a steady state."},
      {"createdAt": "'"$5"'.907000+00:00", "message": "(service api) rolling back to deployment ecs-svc/1."},
      {"createdAt": "'"$5"'.907000+00:00", "message": "(service api) (deployment ecs-svc/2) deployment failed: tasks failed to start."}]'
  fi
  cat >"$WORK/fixture.json" <<JSON
{"services": [{"runningCount": $3, "desiredCount": $4,
  "deployments": [{"status": "PRIMARY", "rolloutState": "$2", "taskDefinition": "$1"}],
  "events": $events}]}
JSON
  export FIXTURE="$WORK/fixture.json"
}

FAILED=0
check() { # check <name> <expect: pass|fail>
  local out code
  out=$("$ROOT/scripts/verify-rollback.sh" "$GOOD" "$BROKEN" "$START" 2>&1)
  code=$?
  if { [ "$2" = pass ] && [ $code -eq 0 ]; } || { [ "$2" = fail ] && [ $code -ne 0 ]; }; then
    echo "ok    $1 (exit $code)"
  else
    echo "WRONG $1: expected $2, got exit $code"
    echo "$out" | tail -5
    FAILED=1
  fi
  unset AWS_EXIT CURL_EXIT
}

fixture "$GOOD" COMPLETED 1 1 2025-10-15T16:28:37
check "automatic rollback to the good version passes" pass

fixture "$GOOD" COMPLETED 1 1 2025-10-15T16:28:37
export AWS_EXIT=254
check "an AWS error (access denied) fails" fail

fixture "$BROKEN" COMPLETED 1 1 2025-10-15T16:28:37
check "the broken version running fails" fail

fixture "$GOOD" COMPLETED 1 1 2025-10-15T16:28:37 no
check "good version back with no rollback events (manual redeploy) fails" fail

fixture "$GOOD" COMPLETED 1 1 2025-10-15T15:00:00
check "a rollback from before this run fails" fail

fixture "$BROKEN" IN_PROGRESS 0 1 2025-10-15T16:28:37
check "no rollback before the timeout fails" fail

fixture "$GOOD" COMPLETED 0 1 2025-10-15T16:28:37
check "good version with no running tasks fails" fail

fixture "$GOOD" COMPLETED 1 1 2025-10-15T16:28:37
export CURL_EXIT=22
check "API health check failing fails" fail

fixture "arn:aws:ecs:eu-west-1:111111111111:task-definition/kestrel-dev-api:4" COMPLETED 1 1 2025-10-15T16:28:37
check "rolled back to some other version fails" fail

exit $FAILED
