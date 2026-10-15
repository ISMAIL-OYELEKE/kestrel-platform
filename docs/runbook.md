# Runbook: Kestrel alarms

Every CloudWatch alarm in `terraform/modules/observability/alarms.tf` links to one section of this page. Each section says what the alarm means, how to confirm it, what to do now, and what to change so it does not come back.

In the commands below, replace `<name>` with `kestrel-dev` or `kestrel-prod`. All resources are in `eu-west-1`. The dashboard for each environment is called `<name>` in CloudWatch and shows every metric used here on one page.

**When an email arrives**

1. Open the dashboard and check the alarm widget at the top. Note which other alarms are red; several alarms together usually share one cause.
2. Check whether a deploy just ran (GitHub Actions, `deploy` workflow). A new release is the most common cause of a sudden change.
3. Work through the section below for the alarm that fired first.
4. When the alarm returns to OK, a second email arrives. Write a short note of what happened and what was changed.

Useful log groups:

| What | Log group |
|---|---|
| API (FastAPI on ECS) | `/kestrel/<name>/api` |
| Scorer (Lambda) | `/aws/lambda/<name>-scorer` |
| Database (PostgreSQL) | `/aws/rds/instance/<name>/postgresql` |
| WAF blocked requests | `aws-waf-logs-<name>` |

Logs never contain a full BVN; the JSON log formatter masks it.

---

## api-5xx-rate

**Meaning.** More than the configured share of API requests in 5 minutes ended in a 5xx error, with at least 20 requests in that window so one failed request on a quiet night does not page anyone. The rate includes errors from the API itself (500) and from the load balancer (502, 503, 504).

**Confirm**

- On the dashboard, compare `HTTPCode_Target_5XX_Count` (the app failed) with `HTTPCode_ELB_5XX_Count` (the load balancer could not reach a healthy task).
- Search the API logs for errors:

  ```
  aws logs tail /kestrel/<name>/api --since 15m --filter-pattern '"level": "ERROR"'
  ```

- If the errors mention the database (connection refused, too many clients, SSL), go to the database checks under [api-no-healthy-tasks](#api-no-healthy-tasks).

**Immediate fix**

- If the errors started with a deploy, roll back by redeploying the previous commit (revert the merge on `main`; the pipeline redeploys). The ECS circuit breaker already rolls back a release whose tasks never become healthy, so a release that is healthy but returns errors needs this manual rollback.
- If errors come from the load balancer and healthy tasks are 0, follow [api-no-healthy-tasks](#api-no-healthy-tasks).

**Permanent fix.** Add a test that reproduces the failing request, and add that path to `scripts/smoke-aws.sh` so the pipeline catches it before the next release.

---

## api-p95-latency

**Meaning.** The slowest 5% of API responses took longer than the threshold in 3 of the last 5 one minute periods. Users are waiting, even if nothing has failed yet.

**Confirm**

- On the dashboard, check whether request count rose at the same time (load) or stayed flat (something got slower).
- Check ECS CPU and memory, and RDS `CPUUtilization`, `DatabaseConnections` and `ReadLatency`.
- Check whether the service is at its maximum task count:

  ```
  aws ecs describe-services --cluster <name> --services api \
    --query 'services[0].{running:runningCount,desired:desiredCount}'
  ```

**Immediate fix**

- If the API is at its maximum task count and CPU is high, raise `api_max_count` in `terraform/envs/<env>/terraform.tfvars` and apply through the pipeline.
- If the database is the slow part, find long queries in `pg_stat_activity` and the PostgreSQL log, and stop the offending query if it is safe to do so.

**Permanent fix.** Add an index or fix the slow query, or move the database to a larger instance class. If load is the cause, lower the autoscaling target for requests per task so new tasks start earlier.

---

## api-no-healthy-tasks

**Meaning.** The load balancer has no API task passing its health check (`/health/live`), so every request gets a 503. This is a full outage.

**Confirm**

- Check why tasks stopped:

  ```
  aws ecs describe-services --cluster <name> --services api \
    --query 'services[0].events[:10].message'
  aws ecs list-tasks --cluster <name> --desired-status STOPPED
  aws ecs describe-tasks --cluster <name> --tasks <task-arn> \
    --query 'tasks[0].{reason:stoppedReason,container:containers[0].reason}'
  ```

- Common reasons: the image cannot be pulled (ECR or the VPC endpoint), the app crashes at start (missing secret or wrong setting, visible in the API log), or the task runs out of memory.

**Immediate fix**

- If a deploy caused it, the circuit breaker should already be rolling back. `scripts/verify-deploy.sh` reports this in the pipeline. If it did not, redeploy the previous commit.
- If the database secret or SSL setting is wrong, fix it in Terraform and apply; tasks restart on their own.
- As a last resort, force fresh tasks:

  ```
  aws ecs update-service --cluster <name> --service api --force-new-deployment
  ```

**Permanent fix.** Add the failure to the smoke test, and add a startup check in the app that fails loudly with a clear message when a setting is missing.

---

## queue-oldest-message

**Meaning.** A loan application has waited more than 5 minutes in the scoring queue for a decision. Scoring is falling behind or has stopped.

**Confirm**

- On the dashboard, check the scorer's `Errors`, `Throttles` and `Duration`, and the queue's messages visible.
- Read the scorer log:

  ```
  aws logs tail /aws/lambda/<name>-scorer --since 15m
  ```

- Check that the event source mapping is enabled:

  ```
  aws lambda list-event-source-mappings --function-name <name>-scorer \
    --query 'EventSourceMappings[0].State'
  ```

**Immediate fix**

- If the scorer is failing on every message, fix the cause (often the database connection or permissions) and let the queue drain. Failed messages are retried, then go to the dead-letter queue.
- If the scorer is healthy but slow, the queue will catch up on its own; watch the oldest message age fall.
- If the mapping is disabled, enable it:

  ```
  aws lambda update-event-source-mapping --uuid <uuid> --enabled
  ```

**Permanent fix.** Raise the scorer's concurrency or memory if it is simply too slow, and add an alarm on scorer errors if this was caused by a silent failure.

---

## dlq-messages

**Meaning.** At least one scoring message failed 3 times and was moved to the dead-letter queue `<name>-scoring-dlq`. That application has no decision yet, and it will not get one until someone acts.

**Confirm**

- Read the failed messages without deleting them:

  ```
  aws sqs receive-message --queue-url "$(aws sqs get-queue-url --queue-name <name>-scoring-dlq --query QueueUrl --output text)" \
    --max-number-of-messages 5 --visibility-timeout 0
  ```

- Find the matching error in the scorer log by the application id in the message.
- Decide whether the message itself is bad (malformed input, will always fail) or the scorer was broken at the time (will succeed once fixed).

**Immediate fix**

- If the scorer is fixed, move the messages back to the main queue with a redrive (SQS console, dead-letter queue, "Start DLQ redrive", or):

  ```
  aws sqs start-message-move-task --source-arn <dlq-arn>
  ```

- If a message is bad, record its application id, mark the application for manual review, then delete the message.

**Permanent fix.** Make the scorer reject a bad message clearly instead of retrying it, and add the case to the scorer's tests.

---

## db-free-storage

**Meaning.** The database has less than 2 GiB of free disk. If it runs out, PostgreSQL stops accepting writes and loan applications fail.

**Confirm**

- On the dashboard, check how fast `FreeStorageSpace` is falling. A steady slope is data growth; a sudden drop is usually logs or a runaway query writing temporary files.
- Check whether storage autoscaling has already grown the disk:

  ```
  aws rds describe-db-instances --db-instance-identifier <name> \
    --query 'DBInstances[0].{allocated:AllocatedStorage,max:MaxAllocatedStorage}'
  ```

**Immediate fix**

- If the disk is near its maximum, raise the `max_allocated_storage_gb` default in `terraform/modules/database/variables.tf` and apply through the pipeline. RDS grows storage without downtime.
- If a query is filling temporary space, stop it.

**Permanent fix.** Set a retention policy for old data, and size the maximum storage for at least 3 months of growth.
