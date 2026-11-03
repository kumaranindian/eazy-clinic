# Patient Documents (Module J)

Metadata `patient_documents` + object `tenants/{tenant}/patients/{patient}/documents/{documentId}` in the private bucket (never public; Storage rules deny all clients). Upload `POST /patients/{id}/documents` (JSON base64, ≤ 3 MB): PDF, PNG, JPEG or WebP, type **detected from the bytes** (declared type must match). Fields: name, category (`previous_report|lab_report|scanned_record|referral|patient_prescription|other`), source, description, `classification` (`normal|restricted` — restricted needs clinical access), uploader/date, `verificationStatus` (`unverified`).

Access: `patient_documents.view/manage` (doctors, nurses; not receptionists/admins). Download `GET …/{id}/content` is authenticated, tenant- and patient-checked (a document id from another patient or clinic answers 404), `no-store`, `nosniff`, **audited**; there are no permanent or public URLs. Time-limited signed URLs are not used (the backend streams, TD-39). Needs the consents described in `CONSENT_MANAGEMENT.md`.

**Retention:** "removal" (`DELETE …?reason=`) hides the document and records who/why; the stored object and metadata are **retained**. Replacement is a new upload. Upload/view/removal are audited. No laboratory workflow exists.
