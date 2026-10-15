#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in --query are JMESPath literals, not shell
# Fails if Amazon ECR's scan of an image found any CRITICAL vulnerability (brief item 6.6).
# The repository scans every image on push. Usage: scripts/scan-gate.sh <repository> <tag>
set -euo pipefail
REPO=${1:?repository}
TAG=${2:?tag}

echo "Waiting for the ECR scan of $REPO:$TAG"
aws ecr wait image-scan-complete --repository-name "$REPO" --image-id imageTag="$TAG"

COUNTS=$(aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" \
  --query 'imageScanFindings.findingSeverityCounts' --output json)
echo "Findings by severity: $COUNTS"

CRITICAL=$(echo "$COUNTS" | python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("CRITICAL", 0))')
if [ "$CRITICAL" -gt 0 ]; then
  echo "Blocked: $CRITICAL critical vulnerabilities:"
  aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" \
    --query 'imageScanFindings.findings[?severity==`CRITICAL`].[name,uri]' --output text
  exit 1
fi
echo "No critical vulnerabilities."
