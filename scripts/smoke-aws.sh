#!/usr/bin/env bash
# End to end check of a deployed environment over HTTPS, with full certificate verification.
# Run from terraform/platform after `terraform apply`:   ../../scripts/smoke-aws.sh
set -euo pipefail

URL=$(terraform output -raw api_url)
API_LOGS=$(terraform output -raw api_log_group)
SCORER_LOGS=$(terraform output -raw scorer_log_group)
CERT=$(mktemp --suffix=.pem)
terraform output -raw certificate_pem > "$CERT"
RUN=$(date +%s)

# --cacert trusts exactly our certificate; nothing here turns verification off.
call() { curl -sS --fail-with-body --cacert "$CERT" "$@"; echo; }

echo "== 1. HTTP is redirected to HTTPS"
curl -sS -o /dev/null -w "%{http_code} -> %{redirect_url}\n" "${URL/https:/http:}/health"

echo "== 2. health over HTTPS (verified certificate)"
call "$URL/health"

echo "== 3. create two applications"
ADA=$(call -X POST "$URL/applications" -H 'content-type: application/json' -H "X-Request-ID: aws-ada-$RUN" \
  -d '{"applicant_name":"Ada Obi","bvn":"22123456789","monthly_salary":150000,"requested_amount":300000}')
BAYO=$(call -X POST "$URL/applications" -H 'content-type: application/json' -H "X-Request-ID: aws-bayo-$RUN" \
  -d '{"applicant_name":"Bayo","bvn":"22123456780","monthly_salary":100000,"requested_amount":900000}')
echo "$ADA"; echo "$BAYO"
id() { python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }

echo "== 4. waiting 10 seconds for the scorer Lambda"; sleep 10
call "$URL/applications/$(echo "$ADA" | id)"
call "$URL/applications/$(echo "$BAYO" | id)"

echo "== 5. the same request IDs in the scorer's logs (API -> queue -> Lambda)"
aws logs filter-log-events --log-group-name "$SCORER_LOGS" --start-time $(( (RUN - 60) * 1000 )) \
  --filter-pattern "\"aws-ada-$RUN\"" --query 'events[].message' --output text | grep decision_notified || echo "not found yet, rerun step 5 in a minute"

echo "== 6. BVN anywhere in API or scorer logs (expect 0 and 0)"
for g in "$API_LOGS" "$SCORER_LOGS"; do
  aws logs filter-log-events --log-group-name "$g" --filter-pattern '"22123456789"' --query 'length(events)'
done

echo "== 7. what an invalid BVN returns (must not echo it back)"
curl -sS --cacert "$CERT" -X POST "$URL/applications" -H 'content-type: application/json' \
  -d '{"applicant_name":"X","bvn":"221234567891","monthly_salary":1,"requested_amount":1}'; echo
rm -f "$CERT"
