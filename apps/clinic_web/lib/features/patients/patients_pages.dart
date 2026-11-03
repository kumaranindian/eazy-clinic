import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validation/validation.dart';

import '../clinic_admin/form_kit.dart';
import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/paged_list.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'patient_providers.dart';

const List<String> _genders = ['male', 'female', 'other', 'undisclosed'];
const List<String> _bloods = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
  'unknown',
];
const List<String> _contactMethods = ['phone', 'sms', 'email', 'whatsapp'];
const List<String> _consentMethods = [
  'in_person_signed',
  'in_person_verbal',
  'digital_form',
  'phone_recorded',
];
const List<String> _guardianChecks = [
  'government_id_sighted',
  'birth_certificate_sighted',
  'court_order_sighted',
  'other_document_sighted',
];

/// Patient directory: search by name, MRN, phone, e-mail or id. Rows show
/// masked contact details and no clinical information.
class PatientsPage extends ConsumerWidget {
  const PatientsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Patients',
      subtitle:
          'Search by name, MRN, phone, e-mail or patient ID. Contact details are masked.',
      path: '/patients',
      searchHint: 'Search patients',
      statusOptions: const ['active', 'inactive', 'archived'],
      extraDropdown: ('Gender', 'gender', _genders),
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No patients found',
      emptyMessage: 'Register a patient, or change the search and filters.',
      actions: [
        if (can(ref, ClinicPermission.patientsCreate))
          EcPrimaryButton(
            label: 'Register patient',
            icon: Icons.person_add_alt,
            compact: true,
            onPressed: () => context.go('/clinic/patients/new'),
          ),
      ],
      rowBuilder: (context, p) => RowCard(
        title: '${p['fullName']}',
        subtitle:
            '${p['mrn']} · ${p['dateOfBirth']} · ${p['maskedPhone']}${p['linked'] == true ? ' · App linked' : ''}',
        status: p['status'],
        onTap: () => context.go('/clinic/patients/${p['patientId']}'),
      ),
    );
  }
}

/// Registers a new patient or edits demographics. Registration needs the
/// patient's own consent (or a verified guardian's for a minor), and shows
/// possible duplicates for review before saving.
class PatientFormPage extends ConsumerStatefulWidget {
  const PatientFormPage({this.patientId, super.key});

  final String? patientId;

  @override
  ConsumerState<PatientFormPage> createState() => _PatientFormState();
}

class _PatientFormState extends ConsumerState<PatientFormPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields([
    'fullName',
    'preferredName',
    'dob',
    'phone',
    'alternatePhone',
    'email',
    'language',
    'occupation',
    'notes',
    'line1',
    'line2',
    'city',
    'state',
    'country',
    'postalCode',
    'gName',
    'gRelationship',
    'gPhone',
    'evidence',
  ]);
  String? _branch;
  String? _gender;
  String? _blood;
  String? _method;
  String? _guardianCheck;
  String _consentMethod = _consentMethods.first;
  bool _consent = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.patientId != null;

  @override
  void initState() {
    super.initState();
    _loaded = !_editing;
    if (!_editing) _f.set('country', 'India');
    _f['dob'].addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _fill(Json p) {
    final a = (p['address'] as Map<String, Object?>?) ?? const {};
    final g = (p['guardian'] as Map<String, Object?>?) ?? const {};
    _f
      ..set('fullName', p['fullName'])
      ..set('preferredName', p['preferredName'])
      ..set('dob', p['dateOfBirth'])
      ..set('phone', p['phone'])
      ..set('alternatePhone', p['alternatePhone'])
      ..set('email', p['email'])
      ..set('language', p['preferredLanguage'])
      ..set('occupation', p['occupation'])
      ..set('notes', p['restrictedNotes'])
      ..set('line1', a['line1'])
      ..set('line2', a['line2'])
      ..set('city', a['city'])
      ..set('state', a['state'])
      ..set('country', a['country'])
      ..set('postalCode', a['postalCode'])
      ..set('gName', g['name'])
      ..set('gRelationship', g['relationship'])
      ..set('gPhone', g['phone']);
    _gender = p['gender'] as String?;
    _blood = p['bloodGroup'] as String?;
    _method = p['preferredContactMethod'] as String?;
    _loaded = true;
  }

  /// A hint to show the guardian section; the backend decides with the
  /// clinic's own minor-age setting.
  bool get _likelyMinor {
    final d = DateTime.tryParse(_f.text('dob'));
    if (d == null) return false;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age < 18;
  }

  Map<String, Object?> _demographics() => {
    'fullName': _f.text('fullName'),
    'preferredName': ?_f.opt('preferredName'),
    'dateOfBirth': _f.text('dob'),
    'gender': _gender,
    'bloodGroup': ?_blood,
    'phone': _f.text('phone'),
    'alternatePhone': ?_f.opt('alternatePhone'),
    'email': ?_f.opt('email'),
    'preferredLanguage': ?_f.opt('language'),
    'preferredContactMethod': ?_method,
    'occupation': ?_f.opt('occupation'),
    'restrictedNotes': ?_f.opt('notes'),
    'address': {
      'line1': _f.text('line1'),
      'line2': ?_f.opt('line2'),
      'city': _f.text('city'),
      'state': _f.text('state'),
      'country': _f.text('country'),
      'postalCode': _f.text('postalCode'),
    },
    if (_f.opt('gName') != null)
      'guardian': {
        'name': _f.text('gName'),
        'relationship': _f.text('gRelationship'),
        'phone': _f.text('gPhone'),
        'verificationMethod': ?_guardianCheck,
      },
  };

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (!_editing && !_consent) {
      setState(
        () => _error =
            'Registration needs the patient\'s consent. Ask them and tick the box only if they agree.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(controlPlaneRepositoryProvider);
    try {
      if (_editing) {
        await repo.sendMap(
          'PATCH',
          '/patients/${widget.patientId}',
          _demographics(),
        );
        ref.invalidate(patientDetailProvider(widget.patientId!));
        if (mounted) context.go('/clinic/patients/${widget.patientId}');
        return;
      }
      Map<String, Object?>? review;
      final check = await repo.sendMap('POST', '/patients/duplicate-check', {
        'fullName': _f.text('fullName'),
        'dateOfBirth': _f.text('dob'),
        'phone': _f.text('phone'),
        'email': ?_f.opt('email'),
      });
      final matches = ((check['matches'] as List?) ?? const [])
          .cast<Map<String, Object?>>();
      if (check['requiresReview'] == true) {
        if (!mounted) return;
        final reason = await _reviewDuplicates(matches);
        if (reason == null) {
          setState(() => _saving = false);
          return;
        }
        review = {
          'decision': 'confirmed_distinct',
          'reason': reason,
          'reviewedPatientIds': [
            for (final m in matches)
              if (m['level'] != 'low') m['patientId'],
          ],
        };
      }
      final minor = _f.opt('gName') != null;
      final saved = await repo.sendMap('POST', '/patients', {
        'branchId': _branch,
        ..._demographics(),
        'consent': {
          'granted': true,
          'textVersion': '1.0',
          'collectionMethod': _consentMethod,
          'evidenceRef': ?_f.opt('evidence'),
          if (minor) 'grantedBy': {'type': 'guardian'},
        },
        'duplicateReview': ?review,
      });
      ref.invalidate(pagedListProvider);
      if (mounted) context.go('/clinic/patients/${saved['patientId']}');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureText(e);
        });
      }
    }
  }

  /// Shows possible duplicates; returns the staff member's reason for
  /// continuing, or null to stop. Nothing is merged either way.
  Future<String?> _reviewDuplicates(List<Map<String, Object?>> matches) =>
      showDialog<String>(
        context: context,
        builder: (context) => _DuplicateDialog(matches),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return AsyncBody(
        value: ref.watch(patientDetailProvider(widget.patientId!)),
        onRetry: () => ref.invalidate(patientDetailProvider(widget.patientId!)),
        builder: (p) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(p));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    final branches =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const [];
    final canVerifyGuardian = can(ref, ClinicPermission.patientsLinkAccount);
    final showGuardian = _likelyMinor || _f.opt('gName') != null;
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: _editing ? 'Edit patient' : 'Register patient',
          subtitle: _editing
              ? 'Identity, MRN and branch cannot be changed here.'
              : 'The clinic ID and MRN are assigned automatically.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(message: _error!),
          ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Section(
                title: 'Personal details',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    if (!_editing)
                      SizedBox(
                        width: 300,
                        child: EcDropdown<String>(
                          label: 'Branch',
                          items: [for (final b in branches) '${b['branchId']}'],
                          value: _branch,
                          itemLabel: (id) =>
                              '${branches.firstWhere((b) => b['branchId'] == id)['name']}',
                          validator: (v) =>
                              v == null ? 'Choose a branch.' : null,
                          onChanged: (v) => setState(() => _branch = v),
                        ),
                      ),
                    TextRow(
                      label: 'Full name',
                      controller: _f['fullName'],
                      validator: (v) => requiredText(v, min: 2, label: 'Name'),
                      maxLength: 100,
                    ),
                    TextRow(
                      label: 'Preferred name',
                      controller: _f['preferredName'],
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'Date of birth (YYYY-MM-DD)',
                      controller: _f['dob'],
                      maxLength: 10,
                      validator: (v) =>
                          DateTime.tryParse((v ?? '').trim()) == null ||
                              (v ?? '').trim().length != 10
                          ? 'Use the format YYYY-MM-DD.'
                          : null,
                    ),
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Gender',
                        items: _genders,
                        value: _gender,
                        itemLabel: Fmt.humanize,
                        validator: (v) => v == null ? 'Choose one.' : null,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Blood group',
                        items: _bloods,
                        value: _blood,
                        onChanged: (v) => setState(() => _blood = v),
                      ),
                    ),
                    TextRow(
                      label: 'Occupation',
                      controller: _f['occupation'],
                      maxLength: 80,
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Contact',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Phone',
                      controller: _f['phone'],
                      validator: (v) => Validators.indianMobile(v)?.message,
                    ),
                    TextRow(
                      label: 'Alternate phone',
                      controller: _f['alternatePhone'],
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.indianMobile(v)?.message,
                    ),
                    TextRow(
                      label: 'Email',
                      controller: _f['email'],
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.email(v)?.message,
                    ),
                    TextRow(
                      label: 'Preferred language (e.g. en, hi)',
                      controller: _f['language'],
                      maxLength: 5,
                    ),
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Preferred contact method',
                        items: _contactMethods,
                        value: _method,
                        itemLabel: Fmt.humanize,
                        onChanged: (v) => setState(() => _method = v),
                      ),
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Address',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Address line 1',
                      controller: _f['line1'],
                      validator: (v) =>
                          requiredText(v, min: 3, label: 'Address'),
                      maxLength: 120,
                    ),
                    TextRow(
                      label: 'Address line 2',
                      controller: _f['line2'],
                      maxLength: 120,
                    ),
                    TextRow(
                      label: 'City',
                      controller: _f['city'],
                      validator: (v) => requiredText(v, min: 2, label: 'City'),
                    ),
                    TextRow(
                      label: 'State',
                      controller: _f['state'],
                      validator: (v) => requiredText(v, min: 2, label: 'State'),
                    ),
                    TextRow(
                      label: 'Country',
                      controller: _f['country'],
                      validator: (v) =>
                          requiredText(v, min: 2, label: 'Country'),
                    ),
                    TextRow(
                      label: 'PIN / postal code',
                      controller: _f['postalCode'],
                      maxLength: 10,
                      validator: (v) => requiredText(v, min: 3, label: 'PIN'),
                    ),
                  ],
                ),
              ),
              if (showGuardian)
                Section(
                  title: 'Guardian (for a minor)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EcInlineMessage(
                        tone: EcStatusTone.info,
                        message:
                            'A minor needs a guardian. Verification is your attestation after seeing a document; a relationship label alone proves nothing.',
                      ),
                      const SizedBox(height: EcSpacing.md),
                      Wrap(
                        spacing: EcSpacing.lg,
                        runSpacing: EcSpacing.lg,
                        children: [
                          TextRow(
                            label: 'Guardian name',
                            controller: _f['gName'],
                            maxLength: 100,
                          ),
                          TextRow(
                            label: 'Relationship',
                            controller: _f['gRelationship'],
                            maxLength: 40,
                          ),
                          TextRow(
                            label: 'Guardian phone',
                            controller: _f['gPhone'],
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? null
                                : Validators.indianMobile(v)?.message,
                          ),
                          if (canVerifyGuardian)
                            SizedBox(
                              width: 300,
                              child: EcDropdown<String>(
                                label: 'Document seen',
                                items: _guardianChecks,
                                value: _guardianCheck,
                                itemLabel: Fmt.humanize,
                                onChanged: (v) =>
                                    setState(() => _guardianCheck = v),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (can(ref, ClinicPermission.historyView))
                Section(
                  title: 'Restricted notes',
                  child: TextRow(
                    label: 'Notes visible to clinical staff only',
                    controller: _f['notes'],
                    width: 620,
                    maxLength: 1000,
                    lines: 3,
                  ),
                ),
              if (!_editing)
                Section(
                  title: 'Consent',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _consentText(),
                        key: const Key('consent-text'),
                        style: EcTypography.body,
                      ),
                      const SizedBox(height: EcSpacing.md),
                      SizedBox(
                        width: 300,
                        child: EcDropdown<String>(
                          label: 'How was it given?',
                          items: _consentMethods,
                          value: _consentMethod,
                          itemLabel: Fmt.humanize,
                          onChanged: (v) => setState(
                            () => _consentMethod = v ?? _consentMethod,
                          ),
                        ),
                      ),
                      const SizedBox(height: EcSpacing.md),
                      TextRow(
                        label: 'Form / reference number (optional)',
                        controller: _f['evidence'],
                        maxLength: 120,
                      ),
                      CheckboxListTile(
                        key: const Key('consent-check'),
                        contentPadding: EdgeInsets.zero,
                        value: _consent,
                        onChanged: (v) => setState(() => _consent = v ?? false),
                        title: Text(
                          showGuardian && _f.opt('gName') != null
                              ? 'The verified guardian has given this consent'
                              : 'The patient has given this consent',
                        ),
                        subtitle: const Text(
                          'Leave unticked unless they clearly agreed.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: EcSpacing.md),
              Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: EcPrimaryButton(
                      label: _editing ? 'Save changes' : 'Register patient',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go(
                            _editing
                                ? '/clinic/patients/${widget.patientId}'
                                : '/clinic/patients',
                          ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _consentText() {
    final catalog = ref.watch(consentCatalogProvider).asData?.value;
    final purposes = ((catalog?['purposes'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    for (final p in purposes) {
      if (p['type'] == 'data_processing') return '${p['text']}';
    }
    return 'I agree that this clinic may collect, store and use my personal and medical information to provide my care.';
  }
}

class _DuplicateDialog extends StatefulWidget {
  const _DuplicateDialog(this.matches);

  final List<Map<String, Object?>> matches;

  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Possible duplicate patients'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EcInlineMessage(
              tone: EcStatusTone.warning,
              message:
                  'Records are never merged automatically. Check these people; if this is a different person, say why and continue.',
            ),
            const SizedBox(height: EcSpacing.md),
            for (final m in widget.matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m['fullName']} · ${m['mrn']}'),
                subtitle: Text(
                  '${m['dateOfBirth']} · ${m['maskedPhone']} · ${Fmt.humanize(m['level'])} match (${((m['reasons'] as List?) ?? const []).map(Fmt.humanize).join(', ')})',
                ),
              ),
            const SizedBox(height: EcSpacing.md),
            EcTextField(
              label: 'Why is this a different person?',
              controller: _reason,
              maxLength: 300,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Go back'),
      ),
      EcPrimaryButton(
        label: 'Different person, continue',
        compact: true,
        onPressed: () {
          final text = _reason.text.trim();
          if (text.length >= 5) Navigator.of(context).pop(text);
        },
      ),
    ],
  );
}
