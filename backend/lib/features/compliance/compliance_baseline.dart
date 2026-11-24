/// Baseline compliance registers for India and the UAE.
///
/// IMPORTANT: these registers are **working checklists drafted by the
/// product team to organise evidence**. They are **not legal advice**, have
/// **not been validated by counsel or any regulator**, and may be incomplete
/// or wrong. Every profile ships with `legalReview.status = pending` and every
/// requirement with `confidence = low`. Nothing here claims that a clinic is
/// compliant, licensed, certified or approved, nor that any authority
/// integration exists. Sources are the authorities' public sites or the
/// titles of the instruments to be confirmed; no clause numbers are cited
/// because none were verified.
const String baselineDraftedOn = '2026-11-05';
const String baselineOwner = 'Avail404 compliance (to be assigned)';

Map<String, Object?> _req(
  String key,
  String title,
  String description, {
  String category = 'statutory',
  String appliesTo = 'facility',
  bool evidenceRequired = true,
  List<String> kinds = const ['policy'],
  bool expiry = false,
  bool goLive = false,
  required String reference,
  String? url,
  String notes = '',
}) => {
  'key': key,
  'title': title,
  'description': description,
  'category': category,
  'appliesTo': appliesTo,
  'evidence': {
    'required': evidenceRequired,
    'kinds': kinds,
    'expiryTracked': expiry,
  },
  'goLiveBlocking': goLive,
  'source': {'reference': reference, 'url': url},
  'draftedOn': baselineDraftedOn,
  'reviewedOn': null,
  'owner': baselineOwner,
  'confidence': 'low',
  'notes': notes.isEmpty
      ? 'Unvalidated draft. Confirm applicability and wording with counsel.'
      : notes,
};

Map<String, Object?> _profile({
  required String key,
  required String title,
  required String countryCode,
  required String jurisdiction,
  required String authorityCode,
  required String authorityName,
  required String authorityUrl,
  required String domain,
  required String appliesWhenNote,
  required List<Map<String, Object?>> requirements,
  List<String> facilityTypes = const [],
}) => {
  'key': key,
  'title': title,
  'countryCode': countryCode,
  'jurisdiction': jurisdiction,
  'authority': {
    'code': authorityCode,
    'name': authorityName,
    'url': authorityUrl,
  },
  'domain': domain,
  'facilityTypes': facilityTypes,
  'appliesWhenNote': appliesWhenNote,
  'requirements': requirements,
  'status': 'published',
  'legalReview': {
    'status': 'pending',
    'reviewedBy': null,
    'reviewedOn': null,
    'notes':
        'Not validated by counsel. Do not rely on this register as legal advice.',
  },
};

List<Map<String, Object?>> baselineProfiles() => [
  // ------------------------------------------------------------------ India
  _profile(
    key: 'in-data-protection',
    title: 'India: personal data protection and patient consent',
    countryCode: 'IN',
    jurisdiction: 'national',
    authorityCode: 'MEITY',
    authorityName:
        'Ministry of Electronics and Information Technology (data protection law)',
    authorityUrl: 'https://www.meity.gov.in',
    domain: 'data_protection',
    appliesWhenNote:
        'Draft assumption: relevant to a clinic that processes patients\' digital personal data in India. Confirm with counsel, including state-level and sector rules.',
    requirements: [
      _req(
        'privacy-notice-consent',
        'Privacy notice and consent for processing patient data',
        'The clinic gives patients a clear notice and records consent for each purpose it processes data for.',
        kinds: ['policy'],
        goLive: true,
        reference:
            'Digital Personal Data Protection Act, 2023 (title only; applicability and clauses to be confirmed)',
      ),
      _req(
        'consent-withdrawal',
        'Consent can be withdrawn and the withdrawal is honoured',
        'Patients can revoke consent and the clinic stops the processing that depended on it.',
        category: 'platform_control',
        appliesTo: 'platform',
        kinds: ['assessment'],
        reference:
            'DPDP Act, 2023 (to be confirmed); EazyClinic product control (Phase 4 consent records)',
      ),
      _req(
        'data-principal-rights',
        'Process for access, correction and erasure requests',
        'A documented way to handle patient requests for access, correction and erasure, including medical-record retention exceptions.',
        kinds: ['policy'],
        reference: 'DPDP Act, 2023 (to be confirmed)',
      ),
      _req(
        'grievance-contact',
        'Named grievance contact for patients',
        'A contact point patients can use for privacy complaints.',
        kinds: ['policy'],
        reference: 'DPDP Act, 2023 (to be confirmed)',
      ),
      _req(
        'breach-response',
        'Personal-data breach response procedure',
        'A written procedure to detect, assess and report personal-data breaches.',
        kinds: ['policy', 'assessment'],
        reference: 'DPDP Act, 2023 (to be confirmed)',
      ),
      _req(
        'retention-review',
        'Medical-record retention and deletion schedule reviewed',
        'Retention periods for clinical and financial records reviewed by counsel; deletion blocked where records must be kept.',
        kinds: ['policy'],
        reference:
            'To be confirmed with counsel (state and professional-body rules vary)',
      ),
      _req(
        'children-guardian-consent',
        'Verifiable guardian consent for children\'s data',
        'Processing of a minor\'s data is based on a guardian\'s verifiable consent.',
        kinds: ['policy'],
        reference: 'DPDP Act, 2023 (to be confirmed)',
      ),
      _req(
        'processor-agreements',
        'Written agreements with data processors',
        'Agreements with cloud, messaging and payment providers that process patient data on the clinic\'s behalf.',
        category: 'contractual',
        kinds: ['agreement'],
        reference: 'To be confirmed with counsel',
      ),
    ],
  ),
  _profile(
    key: 'in-practitioner-registration',
    title: 'India: practitioner registration',
    countryCode: 'IN',
    jurisdiction: 'national',
    authorityCode: 'NMC',
    authorityName: 'National Medical Commission and State Medical Councils',
    authorityUrl: 'https://www.nmc.org.in',
    domain: 'practitioner_registration',
    appliesWhenNote:
        'Draft assumption: relevant to clinics employing registered medical practitioners. Systems of medicine other than allopathy, dental and other professions may be regulated by other bodies; configure per clinic.',
    requirements: [
      _req(
        'practitioner-registration',
        'Each practitioner holds a valid registration',
        'Registration number, issuing council, validity and evidence are recorded for every practitioner (see Credentials).',
        appliesTo: 'practitioner',
        kinds: ['registration'],
        expiry: true,
        goLive: true,
        reference:
            'National Medical Commission / State Medical Councils (instruments to be confirmed)',
      ),
      _req(
        'state-variation-review',
        'State-specific registration and renewal rules reviewed',
        'Differences between states (renewal cycles, additional registrations) reviewed for the clinic\'s state.',
        kinds: ['assessment'],
        reference: 'To be confirmed with counsel per state',
      ),
    ],
  ),
  _profile(
    key: 'in-clinical-establishment',
    title: 'India: clinical establishment registration',
    countryCode: 'IN',
    jurisdiction: 'state',
    authorityCode: 'STATE-HEALTH',
    authorityName:
        'State health department (where a clinical-establishment regime applies)',
    authorityUrl: 'https://www.mohfw.gov.in',
    domain: 'facility_licensing',
    appliesWhenNote:
        'Draft assumption: some states apply a clinical-establishment registration regime and others do not. Applicability must be confirmed per state and facility type.',
    requirements: [
      _req(
        'facility-registration',
        'Facility registration or licence where required',
        'Registration/licence number, authority, validity and evidence for the clinic premises.',
        kinds: ['license', 'registration'],
        expiry: true,
        goLive: true,
        reference: 'State clinical-establishment rules (to be confirmed)',
      ),
      _req(
        'state-rules-review',
        'State rules reviewed and applicability recorded',
        'A written note of which state rules apply to this clinic and why.',
        kinds: ['assessment'],
        reference: 'To be confirmed with counsel',
      ),
    ],
  ),
  _profile(
    key: 'in-abdm-readiness',
    title: 'India: ABDM/ABHA readiness checklist (not an integration)',
    countryCode: 'IN',
    jurisdiction: 'national',
    authorityCode: 'NHA-ABDM',
    authorityName: 'National Health Authority, Ayushman Bharat Digital Mission',
    authorityUrl: 'https://abdm.gov.in',
    domain: 'integration_readiness',
    appliesWhenNote:
        'Optional. EazyClinic has NO live ABDM/ABHA integration and makes no ABDM compliance claim. This checklist only tracks prerequisites a clinic may want before an integration is built and certified.',
    requirements: [
      _req(
        'abdm-facility-registry',
        'Facility prerequisites for the national health registries',
        'Confirm with NHA what facility and practitioner registry entries are needed before integration.',
        category: 'optional_integration',
        kinds: ['assessment'],
        reference: 'ABDM documentation (to be confirmed)',
      ),
      _req(
        'abdm-consent-design',
        'Consent-artefact and data-sharing design reviewed',
        'Design of consent requests, scopes and revocation for health-record sharing reviewed against ABDM requirements.',
        category: 'optional_integration',
        appliesTo: 'platform',
        kinds: ['assessment'],
        reference: 'ABDM documentation (to be confirmed)',
      ),
      _req(
        'abdm-security-prereqs',
        'Security assessment prerequisites',
        'Security testing and documentation required by ABDM before production access.',
        category: 'optional_integration',
        appliesTo: 'platform',
        kinds: ['assessment'],
        reference: 'ABDM documentation (to be confirmed)',
      ),
      _req(
        'abdm-agreements',
        'Participation agreements and sandbox access',
        'Agreements and sandbox credentials obtained through the official onboarding process.',
        category: 'optional_integration',
        kinds: ['agreement'],
        reference: 'ABDM onboarding (to be confirmed)',
      ),
    ],
  ),
  // -------------------------------------------------------------------- UAE
  _profile(
    key: 'ae-dha-dubai',
    title: 'UAE (Dubai): Dubai Health Authority licensing',
    countryCode: 'AE',
    jurisdiction: 'dubai',
    authorityCode: 'DHA',
    authorityName: 'Dubai Health Authority',
    authorityUrl: 'https://www.dha.gov.ae',
    domain: 'facility_licensing',
    appliesWhenNote:
        'Draft assumption: facilities and practitioners licensed in the emirate of Dubai outside free zones. Free-zone facilities (for example healthcare free zones) can fall under a different authority. Never assume every UAE clinic is DHA-regulated; applicability is set per clinic.',
    requirements: [
      _req(
        'facility-license',
        'Facility licence',
        'Facility licence number, issuing authority, validity and evidence.',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'DHA facility licensing (instruments to be confirmed)',
      ),
      _req(
        'practitioner-license',
        'Each practitioner holds a valid professional licence',
        'Licence number, validity and evidence recorded for every practitioner (see Credentials).',
        appliesTo: 'practitioner',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'DHA professional licensing (to be confirmed)',
      ),
      _req(
        'health-information-requirements',
        'Health-information and e-record requirements reviewed',
        'Requirements for health information systems and exchange in Dubai reviewed. EazyClinic has no live DHA integration.',
        kinds: ['assessment'],
        reference: 'DHA publications (to be confirmed)',
      ),
    ],
  ),
  _profile(
    key: 'ae-doh-abu-dhabi',
    title: 'UAE (Abu Dhabi): Department of Health licensing',
    countryCode: 'AE',
    jurisdiction: 'abu_dhabi',
    authorityCode: 'DOH',
    authorityName: 'Department of Health, Abu Dhabi',
    authorityUrl: 'https://www.doh.gov.ae',
    domain: 'facility_licensing',
    appliesWhenNote:
        'Draft assumption: facilities and practitioners licensed in the emirate of Abu Dhabi. Applicability is set per clinic.',
    requirements: [
      _req(
        'facility-license',
        'Facility licence',
        'Facility licence number, issuing authority, validity and evidence.',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'DoH facility licensing (instruments to be confirmed)',
      ),
      _req(
        'practitioner-license',
        'Each practitioner holds a valid professional licence',
        'Licence number, validity and evidence recorded for every practitioner (see Credentials).',
        appliesTo: 'practitioner',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'DoH professional licensing (to be confirmed)',
      ),
      _req(
        'health-information-exchange-review',
        'Health-information-exchange participation requirements reviewed',
        'Any requirement to participate in the emirate\'s health information exchange reviewed. EazyClinic has no live exchange integration.',
        kinds: ['assessment'],
        reference: 'DoH publications (to be confirmed)',
      ),
    ],
  ),
  _profile(
    key: 'ae-mohap-northern-emirates',
    title:
        'UAE (Northern Emirates and federal facilities): Ministry of Health and Prevention',
    countryCode: 'AE',
    jurisdiction: 'northern_emirates',
    authorityCode: 'MOHAP',
    authorityName: 'Ministry of Health and Prevention',
    authorityUrl: 'https://mohap.gov.ae',
    domain: 'facility_licensing',
    appliesWhenNote:
        'Draft assumption: facilities and practitioners licensed by the federal ministry (typically outside Dubai and Abu Dhabi). Applicability is set per clinic.',
    requirements: [
      _req(
        'facility-license',
        'Facility licence',
        'Facility licence number, issuing authority, validity and evidence.',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'MOHAP facility licensing (instruments to be confirmed)',
      ),
      _req(
        'practitioner-license',
        'Each practitioner holds a valid professional licence',
        'Licence number, validity and evidence recorded for every practitioner (see Credentials).',
        appliesTo: 'practitioner',
        kinds: ['license'],
        expiry: true,
        goLive: true,
        reference: 'MOHAP professional licensing (to be confirmed)',
      ),
    ],
  ),
  _profile(
    key: 'ae-health-data-privacy',
    title: 'UAE: health data, privacy and data-residency assessment',
    countryCode: 'AE',
    jurisdiction: 'national',
    authorityCode: 'UAE-FED',
    authorityName:
        'Federal health-data and personal-data protection requirements',
    authorityUrl: 'https://u.ae/en/information-and-services/health-and-fitness',
    domain: 'health_data_residency',
    appliesWhenNote:
        'Draft assumption: relevant to processing patient health data of UAE clinics. Residency and cross-border transfer rules for health data must be assessed with counsel before production; EazyClinic makes no residency or localisation claim.',
    requirements: [
      _req(
        'residency-assessment',
        'Health-data residency and localisation assessment recorded',
        'A written assessment of where patient health data may be stored and processed, signed off by counsel.',
        kinds: ['assessment'],
        goLive: true,
        reference:
            'Federal law on ICT in health fields (title to be confirmed; clauses not cited)',
      ),
      _req(
        'cross-border-transfer',
        'Cross-border transfer assessment',
        'Any transfer of health data outside the UAE (including support access, backups and processors) assessed and documented.',
        kinds: ['assessment'],
        reference: 'To be confirmed with counsel',
      ),
      _req(
        'privacy-notice-consent',
        'Privacy notice and patient consent',
        'Patients receive a privacy notice and consent is recorded for each purpose.',
        kinds: ['policy'],
        goLive: true,
        reference:
            'Federal personal-data protection law (title to be confirmed)',
      ),
      _req(
        'breach-response',
        'Data breach response procedure',
        'A written procedure for detecting, assessing and notifying data breaches.',
        kinds: ['policy'],
        reference: 'To be confirmed with counsel',
      ),
      _req(
        'retention-review',
        'Medical-record retention schedule reviewed',
        'Retention and deletion rules for clinical and financial records reviewed by counsel.',
        kinds: ['policy'],
        reference: 'To be confirmed with counsel',
      ),
      _req(
        'processor-agreements',
        'Written agreements with processors and sub-processors',
        'Agreements with cloud, messaging and payment providers, including data location commitments.',
        category: 'contractual',
        kinds: ['agreement'],
        reference: 'To be confirmed with counsel',
      ),
    ],
  ),
];
