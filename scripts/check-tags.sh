#!/usr/bin/env bash
# Fails if any resource in a Terraform plan is missing a required tag (brief item 10.2).
# Every stack sets the tags as provider default_tags; this check catches a resource that drops
# or overrides them before it is created. It reads tags_all, which Terraform fills in from
# default_tags plus the resource's own tags. Resources that cannot be tagged have no tags_all
# and are skipped.
# Usage: terraform show -json tfplan > plan.json && scripts/check-tags.sh plan.json
set -euo pipefail
PLAN=${1:?plan json file}
REQUIRED='["Environment","Owner","CostCenter"]'

MISSING=$(jq -r --argjson req "$REQUIRED" '
  .resource_changes[]
  | select(.change.after != null and (.change.after | type) == "object" and (.change.after | has("tags_all")))
  | . as $r
  | ($r.change.after.tags_all // {}) as $t
  | ($req - ($t | keys)) as $miss
  | select(($miss | length) > 0)
  | "\($r.address): missing \($miss | join(", "))"' "$PLAN")

CHECKED=$(jq '[.resource_changes[] | select(.change.after != null and (.change.after | type) == "object" and (.change.after | has("tags_all")))] | length' "$PLAN")

if [ -n "$MISSING" ]; then
  echo "Resources without the required tags (Environment, Owner, CostCenter):"
  echo "$MISSING"
  exit 1
fi
echo "Tag check passed: all $CHECKED taggable resources carry Environment, Owner and CostCenter."
