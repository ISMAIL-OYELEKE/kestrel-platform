# Incident challenge, Part A: five support tickets

Each ticket answers the brief's five questions: most likely root cause, how to confirm it, immediate fix, permanent fix, and a two sentence update for the client's CTO. Where more than one cause is plausible, the causes are ranked with the evidence that separates them. Where our own platform already guards against the problem, the file is named.

---

## Ticket 1: Morning 503s

*Every day around 08:00 Lagos time, the load balancer returns 503 for about 4 minutes. ECS scales from 2 to 10 tasks. Task CPU stays under 40%. RDS connections are at the maximum.*

**Most likely root cause, ranked**

1. **Database connection exhaustion caused by the scale-out itself.** Each new task opens its own connection pool. Ten tasks multiplied by the pool size goes past the database's `max_connections`. New tasks then fail their health check (which tests the database), so the load balancer never marks them healthy. Older tasks start failing their checks too, because they cannot get a connection. With no healthy targets left, the load balancer itself answers 503. Low CPU fits this picture: the tasks are waiting for the database, not working.
2. **Scaling starts too late.** The morning rush arrives faster than new tasks can start, so the first minutes are served by 2 tasks. This would show as 504s or slow responses, with fewer 503s, and connections would not be at the maximum.
3. **Long transactions or leaked connections in the app** hold connections open, so the pool never frees up under load.

**How to confirm**

- In CloudWatch, line up for 07:50 to 08:10: `HTTPCode_ELB_503_Count`, `HealthyHostCount` and `UnHealthyHostCount` on the target group, and RDS `DatabaseConnections`. If healthy hosts drop to 0 while connections sit at the maximum, it is cause 1. If healthy hosts stay at 2 or more but latency climbs, it is cause 2.
- Compare `max_connections` (`SHOW max_connections;`) with pool size multiplied by maximum task count.
- In the application logs, look for `too many clients already` or connection timeout errors. In `pg_stat_activity`, count connections per client address and look for `idle in transaction` (cause 3).
- In the ECS service events, check stopped reasons for failed health checks.

**Immediate fix**

- Lower the per task pool size so that the maximum task count multiplied by the pool fits under `max_connections`, with headroom for admin and the scorer.
- Add a scheduled scaling action that raises the minimum to 6 tasks at 07:40 and lowers it at 10:00, so the tasks are warm before the rush instead of starting during it.
- Point the load balancer health check at a liveness check that does not open a database connection, so a busy database stops making healthy tasks look dead.

**Permanent fix**

- Put **RDS Proxy** between the tasks and the database. It pools and reuses connections, so 10 or 50 tasks share a small number of real database connections.
- Size the database for the morning connection load, and cap the service's maximum task count at what the database can serve.
- Scale on request count per task (which reacts to the rush) rather than CPU (which never rises here). Our platform already does this: `terraform/modules/api/autoscaling.tf`.
- Keep a separate liveness check for the load balancer and a deep `/health` for monitoring and alarms.

**Update to the CTO**

> Every morning at 08:00, the extra servers that start for the rush were each opening their own database connections, and together they hit the database's connection limit, which made the load balancer briefly reject requests. We have reduced connections per server and now start the extra servers 20 minutes before the rush, and we are adding a connection pooler this week so it cannot happen again.

---

## Ticket 2: Duplicate decisions

*Some applications get two decision notifications, sometimes one approval and one decline. Scorer is Lambda on SQS. Lambda timeout 60 seconds, visibility timeout 30 seconds. Most runs take under 2 seconds, some up to 45 seconds when the database is busy.*

**Most likely root cause**

The visibility timeout (30 seconds) is shorter than the slowest run (45 seconds). While the first invocation is still working, the message becomes visible again and SQS delivers it to a second invocation. Both score the same application, and both publish a decision, because nothing in the scorer checks whether a decision already exists.

Approval **and** decline for the same application means the scoring result depends on something that changes between the two runs, for example a "total exposure" query that, in the second run, counts the loan the first run just approved. Ranked, the causes of the conflict are: (1) the second run sees the first run's write and declines on affordability; (2) the rule reads data that changes during the day (salary updates, other open loans); (3) a code path with a timeout that defaults to decline.

**How to confirm**

- In the scorer logs, find the duplicated applications: the same SQS `messageId` processed twice, the second time with `ApproximateReceiveCount` of 2, starting about 30 seconds after the first.
- Lambda `Duration` maximum above 30 seconds at the same times, and database latency high.
- For the conflicting pairs, compare the inputs each run read (log them by request ID) to see which value changed between the two runs.

**Immediate fix**

- Raise the queue's visibility timeout to at least 6 times the Lambda timeout (AWS guidance): 360 seconds.
- Make the decision write conditional: `UPDATE ... SET status = $1 WHERE id = $2 AND status = 'PENDING'`, and publish only if a row was updated.
- List every application with two notifications, decide which decision stands, and tell downstream teams before any customer acts on the wrong one.

**Permanent fix**

- Idempotent scoring: lock the row, decide only if still PENDING, record that the notification was sent, all in one transaction. Our scorer does exactly this: `app/src/kestrel/scoring.py`, proven by `test_concurrent_duplicates_give_one_decision`, which runs five copies of one message at once and gets one decision.
- Our queue's visibility timeout is calculated from the Lambda timeout so the two cannot drift apart: `terraform/platform/main.tf` (`6 * local.scorer_timeout`).
- Include the application ID in every event so subscribers can ignore a repeat.
- Fix the slow database queries that cause the 45 second runs, and cap scorer concurrency so it cannot overload the database.

**Update to the CTO**

> A small number of applications were scored twice because a slow scoring run was handed to a second worker before the first one finished, and the two runs sometimes disagreed. We have stopped new duplicates today, are correcting the affected applications with your operations team, and are changing the scorer so an application can only ever receive one decision.

---

## Ticket 3: The NAT bill

*NAT data processing was USD 410 last month, three times forecast. Application traffic did not grow. Most outbound traffic is ECS pulling images from ECR and the app writing documents to S3.*

**Most likely root cause, ranked**

1. **ECR image pulls and S3 writes going through the NAT gateway**, which charges USD 0.048 per GB processed. ECR stores image layers in S3, so every task start downloads the whole image through the NAT. The bill tripled without traffic growth, so the number or size of pulls grew: tasks restarting in a loop (failed health checks, out of memory), more frequent deploys, aggressive scale-in and scale-out, or a much larger image after a base image change.
2. **Cross-AZ NAT traffic.** If tasks in one AZ use a NAT gateway in another, there is also an inter-AZ data charge.
3. **Something unexpected sending data out** (a debug log shipper, a misconfigured backup, or data exfiltration). This must be ruled out, not assumed away.

**How to confirm**

- In Cost Explorer, group by usage type: `NatGateway-Bytes` separates data processing from hourly charges.
- In VPC Flow Logs, sum bytes by destination. Destinations in the S3 and ECR address ranges point to cause 1. Unknown external addresses point to cause 3.
- In ECS service events and CloudTrail, count task starts per day this month against last month, and compare the image size in ECR between versions.

**Immediate fix**

Add an **S3 gateway endpoint** to the private route tables. It is free, takes effect in minutes, and moves both the image layer downloads and the document writes off the NAT gateway. This alone should remove most of the bill.

**Permanent fix**

- Add interface endpoints for `ecr.api` and `ecr.dkr` (and the other AWS services the app calls). Our platform has no NAT gateway at all: `terraform/modules/network/endpoints.tf`, decision in ADR 0006.
- Stop the task churn that caused the extra pulls, and slim the image (multi-stage builds, slim base).
- If a NAT gateway is still needed, use one per AZ so traffic never crosses AZs.
- Turn on AWS Cost Anomaly Detection and a budget alert on the NAT usage type, so a tripling is caught in days, not at month end.

**Update to the CTO**

> Last month's network bill tripled because container images and document uploads were being routed through a paid internet gateway, and more servers were restarting than usual, which multiplied the downloads. We have rerouted that traffic through a free private connection to AWS storage today, and we are adding a cost alert so any similar jump is flagged within days.

---

## Ticket 4: Tasks will not start

*After a routine deploy, every new task in the private subnets fails with `ResourceInitializationError: unable to pull secrets or registry auth`. Old tasks still run. The only infrastructure change was a tightened security group on the VPC endpoints.*

**Most likely root cause, ranked**

1. **The tightened endpoint security group no longer allows HTTPS (443) from the tasks.** Before a Fargate task starts, ECS fetches its secrets from Secrets Manager and an ECR login token, through the interface endpoints. If the endpoint security group no longer admits the tasks' security group or subnets on 443, those calls time out and the task fails with exactly this error. Old tasks are unaffected because they fetched their secrets and image when they started.
2. **The task execution role lost permission** (`secretsmanager:GetSecretValue`, `kms:Decrypt` or the ECR actions).
3. **An endpoint policy or private DNS change**, so the service name no longer resolves to the endpoint.

**What separates them:** in CloudTrail, cause 2 shows `AccessDenied` events for the execution role. Cause 1 shows no event at all, because the request never reached the service.

**How to confirm**

- Compare the endpoint security group's inbound rules with the tasks' security group and subnet ranges.
- VPC Flow Logs on the endpoint network interfaces: `REJECT` records on port 443 from the task subnets.
- VPC Reachability Analyzer from a task network interface to the Secrets Manager endpoint.
- CloudTrail: no `GetSecretValue` calls from the execution role since the deploy, and no `AccessDenied` (rules out cause 2).

**Immediate fix**

Restore the inbound rule on the endpoint security group: HTTPS (443) from the tasks' security group, or from the VPC range. New tasks start on the next ECS retry, with no redeploy. If in doubt, revert the whole security group change, since it is the only change in the release.

**Permanent fix**

- Write endpoint rules against what actually calls the endpoints (the task and Lambda security groups, or the VPC range), and add a comment saying why. Our platform does this, citing this ticket: `terraform/modules/network/security_groups.tf`.
- Apply network changes to dev first and check that a new task starts before promoting to prod.
- Alarm on ECS tasks failing to start (EventBridge rule on stopped tasks with `ResourceInitializationError`), so this pages someone instead of being found after a deploy.

**Update to the CTO**

> After yesterday's release, new application servers could not start because a network rule tightened in the same release also blocked their private access to stored passwords and container images. The servers already running kept serving customers; we have restored the rule so new servers start normally, and network changes will now be tested in our development environment before production.

---

## Ticket 5: Leaked credentials

*GuardDuty reports that temporary credentials of the API's ECS task role are being used from an IP address outside AWS. It is 23:00 on a Friday.*

**First hour, in order**

1. **(0 to 5 minutes) Confirm and declare.** Open the GuardDuty finding (`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`) and note the access key ID, the outside IP, and the first and last seen times. Declare a security incident, start a written timeline, and bring in a second engineer and the security lead. Every step below goes in the timeline with the time.
2. **(5 to 10 minutes) Cut off the stolen credentials.** On the task role, use IAM's **Revoke active sessions**. This adds a deny for every session issued before now, so the stolen temporary credentials stop working immediately, wherever they are used.
3. **(10 to 15 minutes) Restore the service with fresh credentials.** Force a new ECS deployment. New tasks receive new credentials issued after the revocation. Check that the API is healthy and new applications are being scored.
4. **(15 to 35 minutes) Find out what the attacker did.** In CloudTrail, search every event for that access key ID and that IP, across all regions. For our API role the possible actions are: encrypt a BVN (cannot decrypt; there is no decrypt permission), compute BVN lookup hashes, send messages to the scoring queue, and read the **database password secret**.
5. **(35 to 45 minutes) Act on what was reached.** If `GetSecretValue` appears, rotate the database secret now. The database sits in isolated subnets and cannot be reached from the internet, but the password must be treated as known. If `SendMessage` appears, find and hold any fake applications in the queue or database.
6. **(45 to 60 minutes) Find how the credentials left the task.** The usual paths: server side request forgery reaching the task metadata endpoint (169.254.170.2), an endpoint or log that prints environment or credentials, or a compromised dependency or image. Check WAF and application logs for requests to unusual URLs or containing `169.254`, and compare the running image digest with the one the pipeline built. Keep the attacker's IP and indicators for blocking and reporting.
7. **(By 60 minutes) Brief the CTO** with what is known, what is contained, and what is not yet known.

**What I would not do yet, and why**

- **Not delete the task role, the tasks or the stack.** That would take the platform down and destroy the evidence needed to understand the breach. Revoking sessions already makes the stolen credentials useless.
- **Not delete or edit any logs, CloudTrail, GuardDuty findings or images.** They are the evidence, and may be required by the regulator.
- **Not tell customers or the public yet.** First establish whether personal data was actually accessed. The Nigeria Data Protection Act 2023 requires notifying the Commission within 72 hours of becoming aware of a breach that is likely to put people at risk, so that clock is noted in the timeline from minute one.
- **Not rotate or disable the KMS keys.** The API could not decrypt, so the keys are not exposed, and disabling them would make every stored BVN unreadable.
- **Not just redeploy and go to bed.** Until the entry point is found and closed, the attacker can steal fresh credentials the same way.

**Permanent fix**

- **Make stolen task credentials useless outside our network.** Our API role denies every action unless the call comes from our own VPC (`aws:SourceVpc`): `terraform/platform/iam.tf`, statement `DenyOutsideOurVpc`. This works because every AWS call the API makes goes through a VPC endpoint (ADR 0006). With it in place, the attacker's calls from outside AWS would all have been refused.
- Close the actual entry point found in step 6, and add a test for it.
- Alarm on this GuardDuty finding type straight to on-call.

**Update to the CTO**

> Tonight at 23:00, our monitoring detected the API's temporary AWS credentials being used from outside our network; we revoked them within minutes, restarted the service with new credentials, and customers were not affected. We are now confirming exactly what was accessed and how the credentials were taken, and I will update you by 01:00 with findings and whether any customer data was involved.
