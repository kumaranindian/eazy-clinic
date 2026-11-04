# Clinical Templates

`clinical_templates` (scope `clinic` or `doctor`) hold default section content (same section names as a consultation). Using one on `POST /consultations {templateId}` only pre-fills a draft; the doctor edits and nothing is clinical advice.

- `GET/POST /clinical/templates`, `PATCH /clinical/templates/{id}`.
- Clinic scope: `clinical_templates.manage_clinic` (owner/admin). Doctor scope: own templates (`clinical_templates.manage`).
- Inactive templates are refused (`invalid_template`).
- No specialty content ships with the product (Module 12 specialty templates are clinic-authored; TD-53).
