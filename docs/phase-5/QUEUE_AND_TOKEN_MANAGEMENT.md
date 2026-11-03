# Queue and Token Management (Modules I, J, K)

**Queue** = branch + doctor + local date (`queues/{q_<hash>}`; id derived server-side). Created on the first check-in of the day. **Token** = clinic prefix (`queueTokenPrefix`, 1–3 capitals, default `A`) + 3-digit counter, e.g. `A001`; the counter lives on the queue document (`nextToken`), allocated inside the check-in transaction, and every token also has a uniqueness key `queue_tokens/{queueId}_{n}`. The counter restarts each day because a new date is a new queue; old queues and entries stay. Check-in races retry on key collision (tested with concurrent check-ins).

**Entry states:** `waiting → called → in_progress → completed`; `called → skipped → waiting (restore, goes to the end)`; `waiting|called|skipped → cancelled`; `called|skipped → no_show`; `recall` keeps `called` (counts recalls). Final: completed, cancelled, no_show. (`checked_in` is an appointment status: a checked-in patient is a `waiting` entry.) Only one entry per queue can be `in_progress`.

**Ordering** of waiting entries: priority first, then the clinic policy `queueOrdering` — `check_in` (default, by `queuedAt`) or `appointment_time` — ties by token. Priority is set only by `queue.priority` holders (`POST /queue-entries/{id}/priority {priority, reason}`, waiting entries only).

**Permissions:** `queue.operate` (call, recall, skip, restore, cancel, no-show, call-next: reception, nurse, doctor, admin), `queue.consult` (start, complete: doctor, owner), doctors only on their own queue. Cancelling a checked-in patient also needs `appointments.cancel_checked_in`.

**Reads:** `GET /queues?branchId[&date&doctorId]`, `/queues/current?branchId&doctorId[&date]` (summary incl. current/next token), `/queues/{id}`, `/queues/{id}/summary`, `/queues/{id}/entries[?status]`, `/queues/{id}/history`. Summary counts: scheduled, checked in, waiting, called, in consultation, completed, skipped, cancelled, no-show. Entries carry token, patient name, appointment time and source only — no clinical data.

**Live updates:** the queue document has a `version` incremented on every change; the web page polls every 10 s and ignores a snapshot older than the one shown (tested). There are no push or Firestore listeners (clients cannot read Firestore) — TD-44.
