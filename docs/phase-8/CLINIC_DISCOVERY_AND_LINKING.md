# Clinic Discovery and Linking

## Discovery (any signed-in patient account)
`GET /patient/clinics?q=&city=`: active, non-blocked clinics whose plan includes the patient app (max 30). Card: name, description, specialities, address, phone, e-mail, website (from the clinic profile). `GET /patient/clinics/{id}`: adds active branches (name, address, phone, hours), active appointment types, the clinic's working hours and time zone, `bookingMethods`, and `onlinePayments: false`. Suspended, unapproved or not-on-the-app clinics answer 404. Search is by name and address text; a clinic code and geographic search do not exist (TD-69).

`GET /patient/clinics/{id}/doctors?branchId=&q=&speciality=` and `/doctors/{id}`, `/specialities`: only active doctors and only published profile fields (name, designation, qualifications, speciality, experience, languages, consultation fee, biography). Registration numbers, e-mail, phone and date of birth are never returned. There is no per-doctor "verified" flag in the data, so none is claimed. Consultation mode is in person only.

Discovering a clinic grants no access: a newly registered patient sees no appointments, records or bills (tested).

## Linking (existing Phase 4 flow)
1. The patient shows ID at the clinic; staff verify identity and issue a one-time code (`POST /patients/{id}/link-account`, only a hash is stored).
2. The patient enters it under Clinics → *Link with a code* (`POST /patient-accounts/me/link-clinic-record`; needs a verified e-mail; a guardian can link a child's record with a clinic-verified code).
3. The backend validates the code, expiry and single use, prevents taking over a record already linked, and writes the link and an audit entry. A phone number or e-mail alone never links.
4. Unlinking goes through the existing routes subject to retention rules. Several clinics can be linked; records are never merged across clinics.
