#!/usr/bin/env bash
# Local smoke test: sends one application that should be approved and one that should be declined,
# waits for the scorer, then reads both back. Run from app/ after `docker compose up -d`.
set -euo pipefail
API=${API:-http://localhost:8000}

echo "== health"
curl -sf "$API/health"; echo

post() {
  curl -sf -X POST "$API/applications" -H 'content-type: application/json' -H "X-Request-ID: $1" -d "$2"
}

echo "== create (Ada asks for exactly 3x salary, Bayo asks for 9x)"
ADA=$(post smoke-ada '{"applicant_name":"Ada Obi","bvn":"22123456789","monthly_salary":150000,"requested_amount":300000}')
BAYO=$(post smoke-bayo '{"applicant_name":"Bayo","bvn":"22123456780","monthly_salary":100000,"requested_amount":900000}')
echo "$ADA"; echo "$BAYO"

id() { python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
ADA_ID=$(echo "$ADA" | id); BAYO_ID=$(echo "$BAYO" | id)

echo "== waiting 3 seconds for the scorer"; sleep 3

echo "== read back"
curl -sf "$API/applications/$ADA_ID"; echo
curl -sf "$API/applications/$BAYO_ID"; echo

echo "== worker log lines for these two requests"
docker compose logs worker --no-log-prefix | grep -E 'smoke-(ada|bayo)' | grep decision_notified || true

echo "== BVN anywhere in API or worker logs? (expect 0)"
docker compose logs api worker 2>&1 | grep -c -E '22123456789|22123456780' || true
