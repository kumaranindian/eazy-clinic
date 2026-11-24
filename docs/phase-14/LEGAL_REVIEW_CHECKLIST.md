# Legal and Compliance Review Checklist

**Required before any production use.** EazyClinic's registers are product-team drafts. Qualified counsel / local compliance specialists in each country must validate them. Record the outcome in the product (`legalReview` on each register; `confidence` and `reviewedOn` on each requirement) — do not rely on this document alone.

## For every register
- [ ] Is the **authority** correct and still the competent one? Which facility types and jurisdictions does it really cover? (Edit `appliesWhenNote`, `facilityTypes`.)
- [ ] Is each **requirement** accurate, complete and correctly categorised (statutory / contractual / platform control / optional integration)?
- [ ] Is every **source reference** the correct instrument and edition? Add precise citations (the baseline cites none, deliberately).
- [ ] Which **evidence** is actually acceptable (kinds, expiry tracking, original vs. certified copy)?
- [ ] Which requirements are **go-live blocking**?
- [ ] Are **state / emirate / free-zone variations** captured as separate registers rather than assumptions?
- [ ] Set `confidence`, `reviewedOn` and an owner; then set `legalReview` = `reviewed` with reviewer and date.

## India
- [ ] Data protection: applicability to clinics, consent and notice content, children's data, rights handling, breach duties, processors, **retention periods for clinical records** by state and profession.
- [ ] Practitioner registration: council, renewal cycle, systems of medicine other than allopathy, dental and allied professions.
- [ ] Clinical-establishment registration: **which states** apply a regime; facility categories; renewal.
- [ ] ABDM/ABHA: prerequisites and certification path; **confirm EazyClinic does not claim ABDM compliance** until an integration is built and verified.

## UAE
- [ ] Which authority applies to each clinic (DHA / DoH / MOHAP / free-zone authority); never assume one for all.
- [ ] Facility and practitioner licensing rules and renewal; health-information-exchange participation requirements.
- [ ] **Health-data residency / localisation and cross-border transfer**: written assessment; implications for hosting, backups, support access and processors (Phase 21).
- [ ] Federal and local personal-data protection and health-data laws as they apply to the clinic and to EazyClinic as processor.

## Product and process
- [ ] Wording of statuses, disclaimers and alert texts reviewed for any implied approval.
- [ ] Who may act as **platform reviewer**; training and a four-eyes rule if required.
- [ ] Retention and deletion of evidence and credential records.
- [ ] Process for publishing a new register version (impact report → communicate → reassessment window).
- [ ] Terms/contract language between Avail404 and clinics about the nature of this tool.

Sign-off record: reviewer name, firm, date, scope, register versions reviewed, open points.
