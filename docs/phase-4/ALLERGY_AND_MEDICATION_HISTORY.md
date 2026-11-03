# Allergies and Medication History (Modules F, G)

**Allergies** (`patient_allergies`): allergen, category (`drug|food|environmental|insect|latex|other`), reaction, severity (`mild|moderate|severe|unknown`), onset, status (`active|inactive|unverified`), notes, source, verification. A new or edited allergy is **`unverified`** until a doctor verifies it (`active` is only possible when verified). Active/unverified allergies are shown prominently at the top of the patient record with their verification label; when none exist the screen says *"No allergy information recorded. This does not mean the patient has no known allergies."* Permissions: `allergies.view/manage` (nurses may record; doctors verify).

**Medication history** (`patient_medications`): name, generic name, strength, dosage, route, frequency, start/end (end ≥ start), status (`current|completed|discontinued|unknown`, default `unknown`), prescriber, notes, source, verification. It is **history, not a prescription**: there is no prescription endpoint, no recommendation and no interaction logic (Phase 6). Status changes keep earlier versions as revisions.

Both need the `data_processing` consent for new data and are audited on read and write.
