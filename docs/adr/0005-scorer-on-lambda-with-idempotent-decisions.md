# ADR 0005: Run the scorer on Lambda, and make decisions idempotent in the database

Status: Accepted, 15 October 2026

## Context

The brief (item 4.3) asks for scoring decoupled from the API through a queue, on Lambda or Fargate, with the choice justified. Item 4.4 asks that failed messages go to a dead-letter queue and that processing the same message twice never produces two decisions. Incident ticket 2 describes exactly that failure: a 30 second visibility timeout with invocations that sometimes take 45 seconds.

## Decision

1. **Queue:** SQS standard queue with a dead-letter queue (maxReceiveCount 3). An alarm fires on any message in the DLQ.
2. **Worker:** AWS Lambda, triggered by an SQS event source mapping with partial batch responses (`ReportBatchItemFailures`), so one bad message does not make the whole batch retry.
3. **Idempotency lives in the database, not in the queue.** For each message the scorer, in one transaction:
   - locks the application row (`SELECT ... FOR UPDATE`), so a duplicate delivery waits for the first one;
   - decides only if the status is still PENDING (`UPDATE ... WHERE status = 'PENDING'`);
   - publishes the notification only if `notified_at` is empty, then sets it and commits.

   If publishing fails, the transaction rolls back and the message is retried. The rule is deterministic, so a retry reaches the same decision.
4. **Visibility timeout** will be set to 6 times the Lambda timeout (AWS guidance), so a slow invocation is not handed to a second worker while still running. Lambda reserved concurrency caps how many database connections the scorer can open.

## Why Lambda over Fargate

| | Lambda | Fargate worker |
|---|---|---|
| Cost when idle (most of the day for a dev environment) | zero | at least one task running all the time |
| Scaling with queue depth | built into the SQS event source mapping | needs a separate scaling policy on queue depth |
| Fit for the job | each message takes under 2 seconds of work | better for long jobs or heavy, steady load |
| Retries and DLQ | handled by SQS plus partial batch response | written in our own polling loop |

The risk with Lambda is that it scales out quickly and can exhaust database connections. That is handled with reserved concurrency, and with RDS Proxy if the client's volume ever needs it.

## Consequences

- Duplicate SQS deliveries, including the 45 second case from incident 2, produce one decision and one notification. A test with five concurrent copies of the same message proves it (`app/tests/test_scorer.py`).
- Delivery of notifications is "at least once": if the commit fails after SNS accepted the message, the retry publishes the same decision again, possibly with a different `decided_at`. We do not promise exactly once delivery. Each event carries `application_id`, so subscribers can ignore repeats. Two different decisions for one application cannot happen.
- In production the next step would be a transactional outbox, so publishing does not happen while a row lock is held.
- The API and the scorer share one codebase (`app/src/kestrel`) with two entry points, so the business rule is written once.
