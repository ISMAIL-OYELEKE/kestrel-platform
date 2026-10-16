# ADR 0010: Bigger prod tasks and a payday scaling schedule

Status: Accepted, 16 October 2026

## Context

The client's platform goes down almost every month between the 25th and 28th, when salaries land (brief). Our payday peak is 50 requests a second (loadtest/README.md).

The load test in dev on 15 October (item 4.2 trial, docs/evidence/dev-loadtest-trial-*.png) ran at about 23 requests a second against one 0.25 vCPU task:

- 0% of requests failed, but p95 latency reached 14.8 seconds and 409 iterations were dropped.
- The single task sat at about 100% CPU. The database stayed under 8% CPU with at most 12 connections.
- Target tracking did add tasks, but each new task takes a few minutes to start and pass health checks. Until then the one task was overloaded.

So the API tasks were too small, and scaling out started too late for a sudden spike. The database was not the bottleneck.

## Options (Fargate, eu-west-1, October 2026)

| | Cost per task per hour | Prod at 2 tasks, per month |
|---|---|---|
| 0.25 vCPU, 0.5 GB (before) | USD 0.0123 | about USD 18 |
| 0.5 vCPU, 1 GB (chosen) | USD 0.0247 | about USD 36 |

Scaling options considered:

1. **Target tracking only (before).** Free, but it reacts after the load arrives.
2. **Higher minimum all month.** Five tasks all month cost about USD 90 a month and sit idle for 26 days.
3. **Scheduled scaling for the payday window (chosen).** It raises the minimum before the rush and costs extra only for the four days.

## Decision

- Prod tasks get 0.5 vCPU and 1 GB of memory. Dev stays at 0.25 vCPU to save money.
- A scheduled action raises the prod minimum to 5 tasks at 06:00 on the 25th, Lagos time. A second one puts it back to 2 at 23:00 on the 28th. The end is on the 28th, not the 29th, so it also fires in February.
- Both target tracking policies stay on top. If payday traffic is higher than 50 requests a second, they still scale out, up to 20 tasks.

## Cost

The schedule adds 3 tasks for about 89 hours a month: 3 x 89 x USD 0.0247 = about USD 7 a month. With the bigger tasks, the API costs about USD 43 a month at client scale. That is under 3 percent of the USD 1,500 budget.

## Consequences

- `terraform apply` sets the minimum back to `api_min_count`. A deploy during the payday window therefore drops the floor to 2 until the window ends, although target tracking still scales on load. Prod deploys should be frozen from the 25th to the 28th. That is also good practice for the riskiest days of the month.
- The schedule assumes payday is the 25th to the 28th. If the client's customers are paid on other dates, change the two cron expressions in `terraform/modules/api/autoscaling.tf`.
- Each task keeps a database pool of 5 connections. At the 20 task maximum that is 100 connections, close to what db.t4g.micro allows. If payday ever needs more than about 15 tasks, the database class needs reviewing first.
