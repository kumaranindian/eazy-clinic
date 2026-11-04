# Laboratory workflows

## 1. Doctor requests tests
1. In the consultation the doctor chooses **Order tests**, picks a catalogue test, gives the clinical indication and priority.
2. The backend checks the doctor is the consultation's author and the consultation is open, rejects a second active request for the same test, creates `LAB-xxxxxx` in `requested` and the linked investigation request.
3. The doctor sees the order and its status on the consultation. Finalized consultations are not modified by anything that happens later in the laboratory.
4. Cancelling frees the test for a new request.

## 2. Laboratory desk
Accept (or reject with a reason) -> add sample(s) -> collect.

**Collection**: the collector asks the patient to confirm their identity and enters the patient number and the label/barcode text. A wrong number is refused; a label already used in this clinic is refused. The collector and time are recorded. A bad sample is rejected with a reason; **Request recollection** creates a new pending sample and the order returns to `sample_pending`.

## 3. Results
The technician opens **Enter results** for each test and types values. Numeric values must be numbers, qualitative values one of the configured options. The server stores each value with its unit and the flag and range it computed (sex and age come from the order's patient snapshot). Drafts can be saved repeatedly. **Submit for verification** requires every parameter of every test.

## 4. Verification
A different person reviews and **Verify**s, or **Return**s for correction with a reason (results become editable again). A critical flag is displayed prominently; there is no call-back workflow yet (TD-78).

## 5. Publication
**Publish report** (verified orders only) generates the PDF, stores it privately, sets the order to `published`, supersedes any older version and puts a notification in the patient's inbox (push delivery depends on Phase 10 / TD-67).

## 6. Amendment
A technician amends one test's values with a reason. The previous values stay in `revisions`, the order returns to `verification_pending`, and the published report remains the current one until the amendment is verified and republished as version N+1. The patient keeps seeing the last published values until then.

## 7. External laboratory
Define the external laboratory, create a test with `designation: external`, order, collect, **Upload external report**. A second person verifies (this means "reviewed by this clinic", not "tested by this clinic"), then publishes. The report keeps the label "External laboratory report" and the patient sees whether the clinic reviewed it.

## 8. Patient
**Records -> Lab reports** lists current published reports; opening one shows values, flags and the laboratory's reference ranges with a reminder to discuss results with the doctor. The app does not interpret results.
