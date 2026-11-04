# Performance baseline

## Read this first
Everything below ran against the **in-memory store** on the build machine, which has no network and no Firestore. It measures the application code (authentication, validation, logic, serialization) and is a regression baseline. It says **nothing** about Firestore latency, quotas, cost, cold starts, real networks, Android devices or browsers. Those were not measured (no staging, no devices) and are the main open performance item (F-14). Reproduce with `PERF=1 PERF_OUT=perf_results.json dart test test/perf` in `backend/`.

## Measured: API (clinic with 1,500 appointments over 30 days and 400 notifications)
| Request | n | p50 | p95 | max |
|---|---|---|---|---|
| `GET /appointments?date=` (page of 50) | 60 | 7.5 ms | 11.9 ms | 35.0 ms |
| `GET /notifications?limit=20` | 60 | 7.3 ms | 10.1 ms | 15.5 ms |
| `GET /notifications/unread-count` | 60 | 6.3 ms | 7.7 ms | 8.9 ms |
| `GET /reports/appointments` (month, 1,500 rows) | 15 | 14.3 ms | 22.5 ms | 24.3 ms |
| `GET /reports/dashboard` (all six sections) | 8 | 26.5 ms | 32.6 ms | 32.6 ms |
| `GET /laboratory/dashboard` | 15 | 6.7 ms | 8.6 ms | 9.1 ms |
| CSV export of that report (create and store) | 1 | 18 ms | | |
| Report over the 5,200-record scan cap | 1 | 30 ms, `truncated: true`, export refused (422) | | |

## Measured: concurrency
| Scenario | Result |
|---|---|
| 30 clients book the same single-capacity slot at once | exactly 1 created, 29 refused, no server error (161 ms) |
| 8 simultaneous check-ins into one queue | 7 admitted with 7 distinct token numbers, 1 refused by the "too early" rule (50 ms) |
| 150 events processed by 4 workers at once, then dispatched by 4 workers | exactly 150 inbox entries (103 ms) |
| Earlier phases | payment, refund, expense, lab identifier and report publication races are tested with `Future.wait` in their suites |

## Measured: builds and bundles
| Artifact | Size / time |
|---|---|
| Backend executable | 12.5 MB, compiles in about 18 s |
| Clinic Web release | 28.3 MB total of which CanvasKit 19.9 MB (self-hosted); `main.dart.js` 3.6 MB (1.06 MB gzip); about 52 s |
| Doctor Workspace web release | 27.7 MB total; about 39 s |
| Source maps | none emitted |
| Patient Android | not built (no SDK) |

## Query review
196 `DocQuery` call sites: every list is paged or explicitly limited. The few without a limit read plan-bounded sets (seats, branches) or use `count()`. Reports cap at 5,000 records per query and say so. There is no per-row N+1 pattern in the report paths; the new-versus-returning patient lookup reads at most 300 patient documents. 41 composite indexes were added in Phases 9-10 (21 and 20); they are **undeployed**.

## Proposed budgets (for the business owner to approve; nothing here is agreed)
| Budget | Proposal |
|---|---|
| Interactive API reads, server time | p95 < 500 ms on Firestore; alert at p95 > 1 s |
| Writes (booking, payment) | p95 < 1 s |
| Month report with up to 5,000 records | < 3 s |
| Slow-request log line | 2 s (implemented, `request_slow`) |
| Web first load | initial JS under 1.5 MB gzip (now 1.06 MB) and CanvasKit cached |
| Android cold start | under 3 s on a mid-range device (to be measured) |

## Not done
Load tests against Firestore or a deployed backend; Web and Android profiling on low/mid-range devices; Lighthouse; list-rendering profiling with large data; payment and notification load against real providers; cache design (none was added, so nothing can leak across tenants).

## Optimisations made
None were needed by the measurements; the one change that affects efficiency is the report scan cap and refusal to export truncated data. No unverified speed-up was added.
