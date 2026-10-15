// Payday load test (brief item 4.2). Each iteration is one customer: apply for a loan, then check
// the decision once, the way the mobile app does. So each iteration sends 2 requests.
//
// Run from terraform/platform after an apply (see loadtest/README.md):
//   SSL_CERT_FILE=cert.pem k6 run -e BASE_URL=$(terraform output -raw api_url) -e PEAK=15 ../../loadtest/payday.js
//
// PEAK is customers per second at the top of the ramp. Requests per second are twice that.
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL;
const PEAK = Number(__ENV.PEAK || 15);
const RAMP = __ENV.RAMP || "2m";
const HOLD = __ENV.HOLD || "5m";

export const options = {
  scenarios: {
    payday: {
      executor: "ramping-arrival-rate",
      startRate: 1,
      timeUnit: "1s",
      preAllocatedVUs: 50,
      maxVUs: 400,
      stages: [
        { target: PEAK, duration: RAMP }, // salaries land
        { target: PEAK, duration: HOLD }, // the payday peak
        { target: 0, duration: "1m" },
      ],
    },
  },
  // The pass mark: under 1% errors and p95 under 1 second at peak.
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{name:apply}": ["p(95)<1000"],
    "http_req_duration{name:status}": ["p(95)<1000"],
  },
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

// A random 11 digit BVN that is clearly test data (starts with 99), never a real customer's.
function testBvn() {
  let digits = "99";
  for (let i = 0; i < 9; i++) digits += Math.floor(Math.random() * 10);
  return digits;
}

export default function () {
  const headers = { "content-type": "application/json", "X-Request-ID": `load-${__VU}-${__ITER}` };
  const salary = 50000 + Math.floor(Math.random() * 450000);
  const body = JSON.stringify({
    applicant_name: `Load Test ${__VU}`,
    bvn: testBvn(),
    monthly_salary: salary,
    requested_amount: Math.floor(salary * (1 + Math.random() * 6)),
  });

  const created = http.post(`${BASE_URL}/applications`, body, { headers, tags: { name: "apply" } });
  check(created, { "apply: 201": (r) => r.status === 201 });
  if (created.status !== 201) return;

  sleep(2); // the app waits a moment before showing the decision
  const id = created.json("id");
  const status = http.get(`${BASE_URL}/applications/${id}`, { headers, tags: { name: "status" } });
  check(status, { "status: 200": (r) => r.status === 200 });
}
