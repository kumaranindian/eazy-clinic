# Walk-in Management (Module F)

`POST /appointments/walk-in` (header `Idempotency-Key`): `patientId, doctorId, branchId, typeId, notes?, priority?`. Registration of a new patient uses the Phase 4 flow first (UI links to it).

The server uses the branch's local **today** and picks the **nearest slot with room whose end is still in the future** (the slot in progress counts), so availability, breaks, leave and capacity are respected. If nothing is left → 409 "No capacity is left today… cannot overbook"; there is deliberately **no overbooking policy** in Phase 5. The appointment has `source: walk_in`, status `checked_in`, a queue entry and token (e.g. `A001`) created in the same transaction. Priority needs `queue.priority` (owner/admin). Duplicate patients are not created: the patient must exist.
