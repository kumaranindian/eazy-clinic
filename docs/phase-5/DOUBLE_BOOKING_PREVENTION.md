# Double-Booking Prevention

**Mechanism.** For every booking the backend creates one `appointment_slot_reservations` document per **5-minute cell** (and per lane) the appointment occupies, in the **same atomic commit** as the appointment: id `{doctorId}_{date}_{cell}_{lane}`, written with a does-not-exist precondition. Two bookings that need the same cell in the same lane cannot both commit, whatever their length, type or branch — the second gets `AlreadyExists` and the booking is retried against fresh data, ending in 409 "just taken". Reservations are keyed by **doctor and date**, so a doctor cannot be in two branches at once. `maxPerSlot = n` gives n lanes: n bookings fit, the n+1st is refused. Reservations include the buffer after the appointment. Cancelling, no-show and rescheduling delete the reservations in the same commit as the status change.

**Why not only transactions.** Firestore's emulator serializes transactions pessimistically and real transactions can retry; the reservation keys give a hard uniqueness guarantee that does not depend on isolation. The slot list is advisory; the transaction re-reads occupancy.

**Idempotency.** `Idempotency-Key` (8–64 chars) + a hash of the request body is stored in `appointment_idempotency/{hash(uid,key)}` in the booking commit. Same key and body → the original appointment is returned (200, `idempotentReplay: true`); same key, other body → 409; concurrent duplicates all resolve to one appointment. Appointment references are unique via `appointment_references/{ref}` keys.

**Tests.** Six concurrent bookings for one slot → exactly one 201; five concurrent for capacity 2 → two; overlapping types, two branches, replay, key reuse (see `TEST_REPORT.md`). The emulator test checks the same on the real Firestore REST store (sequentially, plus the contract suite's concurrent-create test).

**Limit.** With capacity > 1 the lanes are not per branch: set capacity > 1 only for a doctor who works at a single branch at that time (TD-45).
