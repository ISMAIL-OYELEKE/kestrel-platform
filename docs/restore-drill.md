# Database restore drill (brief items 9.1 and 9.2, DL7)

Run on 16 Oct 2026 against **prod** (`kestrel-prod`, PostgreSQL on RDS, db.t4g.micro, Multi-AZ, 7 day backup retention) with `scripts/restore-drill.sh`. Every time below is West Africa Time (WAT, UTC+1). The script logs in UTC, so the UTC time from its output is in brackets, to match the screenshots in `docs/evidence/`.

## What the drill simulates

Someone deletes or corrupts data by mistake, and nobody notices for about 10 minutes. Multi-AZ does not help here: the standby copies the mistake within seconds. The only way back is a point in time restore to just before the mistake, then pointing the application at the restored copy.

To prove the restore went to the right moment, the drill creates two loan applications through the public API:

- **before**: created before the restore point. It must still be there after the restore.
- **after**: created after the restore point. It stands in for "the damage" and must be gone.

## Timeline

| Time (WAT) | (UTC from the log) | Step | Evidence |
|---|---|---|---|
| 12:36:51 | 11:36:51 | Marker "before" created, application `669d1968-5a98-4a52-901e-7485f3d198f4` | prod-restore-drill-marker-before.png |
| 12:37:30 | 11:37:30 | **Restore point** chosen: 11 min 27 s before the restore was requested, just before the deliberate loss | |
| 12:47:26 | 11:47:26 | Marker "after" created, application `cdaa2158-24fb-4dc8-b8d3-1293d5f9e1f4` | prod-restore-drill-marker-after.png |
| 12:48:57 | 11:48:57 | **Restore requested** (clock starts). AWS reported the latest restorable time as 12:44:13 | prod-restore-drill-restore-requested.png |
| 13:03:35 | 12:03:35 | Restored copy `kestrel-prod-restored` available | prod-restore-drill-restore-available.png |
| 13:04:49 | 12:04:49 | Started pointing the application at the copy: new task definition revision with only `DB_HOST` changed, and the scorer Lambda's `DB_HOST` changed | prod-restore-drill-point.png |
| 13:10:01 | 12:10:01 | **API stable on the restored copy** (clock stops) | prod-restore-drill-point.png |
| 13:11:47 | 12:11:47 | Check: "before" HTTP 200 (found), "after" HTTP 404 (gone). The copy holds exactly the data from 12:37:30 | prod-restore-drill-check.png |
| 13:13:09 | 12:13:09 | Started pointing the application back at the original database | prod-restore-drill-back.png |
| 13:16:17 | 12:16:17 | Back on the original database | prod-restore-drill-back.png |
| 13:17:40 | 12:17:40 | Check on the original database: "before" HTTP 200 and "after" HTTP 200. Nothing was lost on prod | prod-restore-drill-full-log.png |
| 13:18:32 | 12:18:32 | Deleting the restored copy (`cleanup`) | prod-restore-drill-full-log.png |
| 13:20:05 | 12:20:05 | Restored copy deleted. Nothing from the drill is left running | prod-restore-drill-full-log.png |

## How long each step took

| Step | Duration |
|---|---|
| RDS builds the restored copy (12:48:57 to 13:03:35) | 14 min 38 s |
| Operator starts the switch (13:03:35 to 13:04:49) | 1 min 14 s |
| API tasks replaced and healthy on the copy (13:04:49 to 13:10:01) | 5 min 12 s |
| **Measured recovery time (RTO)** | **21 min 4 s** |
| Switch back to the original (13:13:09 to 13:16:17), not part of recovery | 3 min 8 s |

## Against the targets (9.2)

**RTO target 2 hours, measured 21 minutes.** Well inside, with about 1 hour 39 minutes to spare. The measured time starts when the restore is requested. A real incident also needs time to notice the problem, decide to restore and choose the restore point, and the drill does not include that. The spare time is what pays for it, so the 2 hour target holds as long as detection and decision take under about an hour and a half. The alarms (5xx rate, p95 latency, dead letter queue) and the incident playbook in `docs/incidents.md` exist to keep that part short.

Two things would make a real restore slower than this drill:

- **Database size.** The drill database is tiny. RDS restores from the last daily snapshot and then replays the change log up to the chosen second, so a bigger database or a restore point long after the last snapshot takes longer. Building the copy (14 min 38 s) was 70% of the recovery time.
- **A Multi-AZ copy.** The drill restored a single AZ copy to save cost. Restoring as Multi-AZ, as a real recovery should, adds a few minutes while the standby is built.

**RPO target 15 minutes. Newest restorable point at request: 4 min 44 s old.** This is the backup lag, not the point the drill chose (11 min 27 s back, on purpose). When the restore was requested at 12:48:57, AWS could restore to any second up to 12:44:13, which is 4 min 44 s earlier. RDS ships the database's change log to S3 every 5 minutes, so a restore to the newest point typically loses about 5 minutes of writes. That is AWS's typical lag, not a guarantee. That is inside the 15 minute target with no extra cost. If the client ever needs less, the next step is a cross region read replica or AWS Backup with continuous backup, not more frequent snapshots.

## What we would change before relying on this in a real incident

- **The restored copy is outside Terraform.** That is deliberate: during an incident you restore first and tidy up later. Afterwards, the code has to catch up: either import the restored instance into Terraform as the new database, or restore into the original name after renaming the damaged one, so that `terraform apply` does not point the application back at the damaged database.
- **Credentials.** RDS manages and rotates the database password in Secrets Manager. The restored copy has the password that was current at the restore point. If a rotation happened between the restore point and the restore, the application would need the older secret version. It did not happen in this drill.
- **Deploy headroom.** Pointing the application at the copy is a normal rolling deploy, so it needs room in the account's 12 vCPU Fargate quota (see ADR 0010). During the drill only 2 tasks were running, so it fitted. During a payday peak it might not, which is one more reason to raise the quota before go-live.

## What the numbers mean, in one paragraph

In this small database drill, ECS was stable 21 min 4 s after the restore was requested, and the first data check (old marker present, new marker gone) completed at 22 min 50 s. The chosen recovery point was 11 min 27 s before the request; the newest available point lagged by 4 min 44 s. A full production recovery also needs a check that new applications are scored on the restored database, write fencing, and reconciliation of queued work, below.

## Before switching to a restored copy in a real incident

- **Stop new writes first.** Scale the API to zero or block `POST /applications` at the WAF, and set the scorer's concurrency to zero. Otherwise old and new tasks can write to different databases during the switch.
- **Reconcile the queue.** A restore rewinds the database, not SQS or SNS. Keep the queue: messages for applications that are not in the restored copy go to a hold list for review, not to be purged. Notifications already sent cannot be recalled, so list them for the client.
- **Check the result, then resume.** Submit one new test application, confirm it gets a decision and a notification, and only then stop the recovery clock and reopen intake.
- The drill's check script prints HTTP codes for a person to read; it does not fail by itself. Making it fail on a wrong result is a known improvement.

## How to run it again

From `terraform/platform`, with the target environment's backend initialised:

```
../../scripts/restore-drill.sh marker before
# wait at least 10 minutes
../../scripts/restore-drill.sh marker after
../../scripts/restore-drill.sh restore <a UTC time between the two markers>
../../scripts/restore-drill.sh point
../../scripts/restore-drill.sh check     # before 200, after 404
../../scripts/restore-drill.sh back
../../scripts/restore-drill.sh check     # both 200 on the original
../../scripts/restore-drill.sh cleanup   # always before terraform destroy
```

The script writes every step with a UTC timestamp to `restore-drill.log` (not committed).
