#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in --query are JMESPath literals, not shell
# Fails if Amazon ECR's scan of an image found any CRITICAL vulnerability (brief item 6.6).
# The repository scans every image on push. Usage: scripts/scan-gate.sh <repository> <tag>
set -euo pipefail
REPO=${1:?repository}
TAG=${2:?tag}

# --no-paginate: while a scan is still IN_PROGRESS the response has no findings list, and the
# AWS CLI's automatic paging then crashes with "'NoneType' object does not support item assignment".
IMAGE=(--repository-name "$REPO" --image-id imageTag="$TAG")
FINDINGS=(aws ecr describe-image-scan-findings --no-paginate "${IMAGE[@]}")

# The scan record can take a few seconds to appear after the push, so poll instead of using
# `aws ecr wait`, which gives up at once on ScanNotFoundException. If no scan has started after
# 30 seconds, start one: ECR allows one manual scan per image per day.
echo "Waiting for the ECR scan of $REPO:$TAG"
STATUS=""
for i in $(seq 1 60); do # up to 10 minutes
  if STATUS=$("${FINDINGS[@]}" --query 'imageScanStatus.status' --output text 2>scan.err); then
    echo "Scan status: $STATUS"
    case "$STATUS" in
      COMPLETE | ACTIVE) break ;;
      FAILED | UNSUPPORTED_IMAGE | SCAN_ELIGIBILITY_EXPIRED | FINDINGS_UNAVAILABLE)
        echo "The image could not be scanned ($STATUS), so it cannot be cleared for deployment."
        exit 1
        ;;
    esac
  elif grep -q ScanNotFoundException scan.err; then
    echo "No scan yet"
    if [ "$i" -eq 3 ]; then
      echo "Starting a scan"
      aws ecr start-image-scan "${IMAGE[@]}" >/dev/null
    fi
  else
    cat scan.err
    exit 1
  fi
  sleep 10
done
rm -f scan.err
if [ "$STATUS" != "COMPLETE" ] && [ "$STATUS" != "ACTIVE" ]; then
  echo "Timed out waiting for the scan."
  exit 1
fi

COUNTS=$("${FINDINGS[@]}" \
  --query 'imageScanFindings.findingSeverityCounts' --output json)
echo "Findings by severity: $COUNTS"

CRITICAL=$(echo "$COUNTS" | python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("CRITICAL", 0))')
if [ "$CRITICAL" -gt 0 ]; then
  echo "Blocked: $CRITICAL critical vulnerabilities:"
  "${FINDINGS[@]}" \
    --query 'imageScanFindings.findings[?severity==`CRITICAL`].[name,uri]' --output text
  exit 1
fi
echo "No critical vulnerabilities."
