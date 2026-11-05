# Rollback and recovery

## Principles
Prefer **rolling the application back** over touching data. All schema changes so far are additive, so the previous backend and app versions keep working against the current data.

| Change | Rollback | Limit |
|---|---|---|
| Backend release | Redeploy the previous image/revision (Cloud Run: shift traffic to the previous revision) | Notification events created meanwhile stay in the outbox and are processed by the older code only if it knows their types; unknown types fall back to their stored text |
| Web apps | Redeploy the previous build; invalidate caches (`index.html` is `no-store`) | Users with the old bundle open keep it until reload |
| Android | Halt the staged rollout; promote the previous build only by publishing a higher versionCode with the old code (store builds cannot be un-published for devices that updated) | Treat Android as forward-fix |
| Indexes | Additive; leave in place | Removing an index breaks queries that need it |
| Rules | Redeploy previous rules file from Git | Rules are deny-all; rollback has no data effect |
| Data corruption | Restore into a new database from backup/PITR and reconcile; never edit production by hand without a ticket and a second approver | Writes after the recovery point are lost unless replayed from audit logs |

## Forward-fix vs rollback
Roll back when: authentication or tenant isolation is wrong, data is being corrupted, the service is down. Forward-fix when: a defect is cosmetic or isolated, or a rollback would strand data written by the new version.

## Recovery sequence for a bad release
1. Stop the damage: pause traffic or the affected feature (notification channels can be paused per clinic).
2. Roll back the application tier.
3. Assess data written during the window (audit logs per module record who did what; financial and clinical records are append-only/versioned, so corrections are amendments, not edits).
4. Restore from backup only if records are damaged, following `BACKUP_AND_RESTORE.md`.
5. Verify with the smoke tests; communicate (see `INCIDENT_RESPONSE.md`); write the post-incident review.

## Not verified
No rollback was rehearsed (no deployed environment). The first staging deployment must include one rehearsed backend rollback and one rules rollback.
