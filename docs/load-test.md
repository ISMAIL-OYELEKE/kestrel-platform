# Load test results (brief item 4.2, DL6)

Run on 16 Oct 2026 against **prod** with the k6 script `loadtest/payday.js`. Times are West Africa Time (WAT, UTC+1); AWS showed UTC, which is in brackets.

## What we tested

The brief says traffic rises about 25 times above normal on payday, but gives no request rate, so we defined one (`loadtest/README.md`):

| | Customers per second | Requests per second |
|---|---|---|
| Normal busiest hour | 1 | 2 |
| Payday peak (25x) | 25 | 50 |

Each simulated customer applies for a loan, waits 2 seconds, then checks the decision: two requests. The test ramps from 1 to 25 customers a second over 2 minutes (salaries landing), holds 25 a second for 5 minutes, then ramps down. It passes when fewer than 1% of requests fail and the p95 latency of both requests stays under 1 second.

Prod at the time: 2 API tasks of 0.5 vCPU and 1 GB across 2 AZs, PostgreSQL db.t4g.micro Multi-AZ, scorer Lambda with at most 5 at once. Auto scaling adds a task when a task serves more than 600 requests a minute or passes 60% CPU, up to 20 tasks. The WAF limit per IP was raised for the test window only, because k6 runs from one machine, then put back to 2,000 (evidence `prod-redeploy-after-rollback-success.png`).

## Results

| Measure | Result | Target |
|---|---|---|
| Requests | 19,602 in 8 minutes | |
| Failed requests | 0.00% | under 1% |
| Checks passed | 100% | |
| p95 latency, all requests | 58 ms | under 1 s |
| p95, apply for a loan | 67 ms | under 1 s |
| p95, check the decision | 25 ms | under 1 s |
| Iterations | 9,801 complete, 0 interrupted, 8 dropped | |
| 5xx rate on the dashboard | 0% | alarm above 5% |
| Alarms | none fired | |

Dropped iterations are customers k6 wanted to start but could not, because all its virtual users were busy. 8 out of 9,801 is under 0.1% and none of them reached the API.

## Scaling behaviour

| Time (WAT) | (UTC) | What happened |
|---|---|---|
| about 11:54 | about 10:54 | Test starts with 2 tasks running |
| 11:59:59 | 10:59:59 | Auto scaling sets the desired count to 5 (requests per target above 600 a minute) |
| about 12:02 | about 11:02 | Test ends |
| 12:02:59 | 11:02:59 | Desired count set to 13 |

The 2 tasks of 0.5 vCPU carried the whole peak by themselves at about 34% CPU, so the new tasks were not needed to pass. Scaling out was still worth proving: it is what protects the service when payday traffic is higher than our estimate.

The jump to 13 is an overshoot. A new task takes a few minutes to start and pass the load balancer health checks. Until then, requests per healthy task stay high, so target tracking keeps adding. Scale in follows once load stays low for the 300 second cooldown. The cost is a few minutes of extra tasks. The risk is the account's Fargate vCPU quota (12 vCPUs, so 24 tasks of 0.5 vCPU): the overshoot left about 12 tasks running, and the next deploy needed double that and was rolled back (ADR 0010). Before go-live: raise the quota to at least 40 vCPUs and keep the payday deploy freeze.

The database was never the bottleneck: at most 20 connections, and the queue and dead-letter queue stayed empty, so the scorer kept up with every application.

## Compared with the dev trial on 15 Oct

The same script at 15 customers a second against dev (one task of 0.25 vCPU at first) did not fail any requests but p95 reached 14.8 seconds. That task sat at 100% CPU while new tasks were still starting. This is why prod tasks are twice the size and why prod has a scheduled minimum of 5 tasks from 06:00 on the 25th to 23:00 on the 28th (ADR 0010). The prod run shows that change working: 58 ms instead of 14.8 s at a higher load.

## Graphs and raw output

All in `docs/evidence/`:

- `prod-loadtest-k6-summary.png`, `prod-loadtest-k6-summary-end.png`: the k6 summary
- `prod-loadtest-dashboard-api-peak.png`, `prod-loadtest-dashboard-api-after.png`: request rate, error rate and p95 latency during and after the peak
- `prod-loadtest-dashboard-tasks-db-peak.png`, `prod-loadtest-dashboard-tasks-after.png`: running tasks, CPU, database connections, queue and dead-letter queue
- `prod-loadtest-scaling-activities.png`: the auto scaling events
- `dev-loadtest-trial-*.png`: the dev trial for comparison

The dashboard screenshots show us-east-1 in the address bar. CloudWatch dashboards are global and every widget pins eu-west-1 (see the note in `docs/evidence/README.md`).

## Limits of this test

- One machine sends all the traffic. Real payday traffic comes from many phones and networks, so the WAF limit per IP would not be reached.
- The test database is small. A database with 180,000 customers and years of applications makes reads slower, so the 58 ms is a lower bound.
- The peak was held for 5 minutes. A real payday lasts hours, which the scheduled minimum of 5 tasks is for.

## Run it again

See `loadtest/README.md`. Raise `waf_rate_limit` in the environment's tfvars before the run and put it back after.
