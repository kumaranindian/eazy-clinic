# Patient Queue Workflow

`GET /patient/clinics/{c}/appointments/{a}/queue` returns, for the patient's own appointment only: appointment status, queue status, **their** token, queue position, **the number of patients ahead**, the currently served token, and `estimatedWait: null` with a note that a waiting time is not promised.

Never returned: other patients' names, phones, tokens beyond the one being served, appointment details or any medical data (tested by searching the response for a patient waiting ahead). Before check-in the answer is `not_in_queue`. Another account or another clinic id answers 404.

The app refreshes every 15 seconds while the visit is checked in and has a manual Refresh button; it shows the backend's snapshot and does not extrapolate. Real-time push is Phase 10 (polling is used, as in the clinic apps; TD-44).
