# Load test (brief item 4.2)

`payday.js` is a [k6](https://k6.io) script. Each iteration is one customer: apply for a loan, wait 2 seconds, then check the decision. So one customer per second means two requests per second.

## Traffic profile

The brief gives 180,000 customers and a payday peak about 25 times normal, but no request rate, so we define one:

| | Customers per second | Requests per second | Why |
|---|---|---|---|
| Normal busiest hour | 1 | 2 | 3,600 customers in one hour, 2% of the customer base, a generous normal day |
| Payday peak (25x) | 25 | 50 | The brief's multiplier on that busiest hour |

The test ramps from 1 customer per second to `PEAK` over 2 minutes (salaries land), holds the peak for 5 minutes, then ramps down. It passes when fewer than 1% of requests fail and the p95 latency of both requests stays under 1 second.

Auto scaling adds a task when a task serves more than 600 requests a minute (10 per second) or its CPU passes 60% (`terraform/modules/api/autoscaling.tf`). At the 50 requests per second peak that means at least 5 tasks; prod allows up to 20.

## The WAF rate limit

The WAF blocks any single IP address that sends more than `waf_rate_limit` requests in 5 minutes (2,000 normally). A load test runs from one machine, so it looks exactly like the flood that rule is there to stop. For the test window the environment's `waf_rate_limit` is raised in its tfvars, and it is put back afterwards. Real payday traffic comes from thousands of phones, each far below the limit.

## Run it

From `terraform/platform`, after the environment is deployed:

```
terraform output -raw certificate_pem > cert.pem
SSL_CERT_FILE=cert.pem k6 run -e BASE_URL=$(terraform output -raw api_url) -e PEAK=15 \
  --summary-export=summary.json ../../loadtest/payday.js
```

`SSL_CERT_FILE` makes k6 trust exactly our certificate, so TLS stays verified. Each test application uses a made up BVN starting with 99.

Watch the environment's CloudWatch dashboard during the run: requests, p95 latency, running tasks and queue depth.
