import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validation/validation.dart';

import '../../control_plane/data/control_plane_repository.dart';
import '../../shared/ui_helpers.dart';
import '../../shared/ui_kit.dart';

const _clinicTypes = [
  'general_medicine',
  'paediatrics',
  'dentistry',
  'dermatology',
  'gynaecology',
  'physiotherapy',
  'multi_specialty',
  'other',
];

/// Clinic registration application. Submitting creates an application for
/// review; it grants no access and no clinic until a platform admin approves.
class ApplyPage extends ConsumerStatefulWidget {
  const ApplyPage({super.key});

  @override
  ConsumerState<ApplyPage> createState() => _ApplyPageState();
}

class _ApplyPageState extends ConsumerState<ApplyPage> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'name',
      'registrationNumber',
      'clinicEmail',
      'clinicPhone',
      'website',
      'description',
      'line1',
      'line2',
      'city',
      'state',
      'country',
      'postalCode',
      'ownerName',
      'ownerEmail',
      'ownerPhone',
      'designation',
      'doctors',
      'staff',
      'patients',
    ])
      k: TextEditingController(),
  };
  String _type = 'general_medicine';
  bool _submitting = false;
  String? _error;
  List<String> _issues = const [];

  @override
  void initState() {
    super.initState();
    _c['country']!.text = 'India';
    final auth = ref.read(authControllerProvider);
    if (auth is Authenticated) {
      _c['ownerName']!.text = auth.user.displayName ?? '';
      _c['ownerEmail']!.text = auth.user.email ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v, {int min = 1, String label = 'This field'}) =>
      (v ?? '').trim().length < min ? '$label is required.' : null;

  String? _opt(String? v) => null;

  String? _count(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 0 ? 'Enter a whole number (0 or more).' : null;
  }

  String? _email(String? v) => Validators.email(v)?.message;
  String? _phone(String? v) => Validators.indianMobile(v)?.message;

  String? _pin(String? v) {
    final t = (v ?? '').trim();
    if (_c['country']!.text.trim().toLowerCase() == 'india') {
      return RegExp(r'^[1-9][0-9]{5}$').hasMatch(t)
          ? null
          : 'Enter a valid 6-digit PIN code.';
    }
    return t.length < 3 ? 'Enter a postal code.' : null;
  }

  String? _url(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final u = Uri.tryParse(t);
    return u != null &&
            (u.scheme == 'http' || u.scheme == 'https') &&
            u.host.isNotEmpty
        ? null
        : 'Enter a full http(s) address.';
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    String t(String k) => _c[k]!.text.trim();
    String? opt(String k) => t(k).isEmpty ? null : t(k);
    setState(() {
      _submitting = true;
      _error = null;
      _issues = const [];
    });
    final body = <String, Object?>{
      'clinic': {
        'name': t('name'),
        'type': _type,
        'registrationNumber': ?opt('registrationNumber'),
        'email': t('clinicEmail'),
        'phone': t('clinicPhone'),
        'website': ?opt('website'),
        'description': ?opt('description'),
      },
      'address': {
        'line1': t('line1'),
        'line2': ?opt('line2'),
        'city': t('city'),
        'state': t('state'),
        'country': t('country'),
        'postalCode': t('postalCode'),
      },
      'owner': {
        'fullName': t('ownerName'),
        'email': t('ownerEmail'),
        'phone': t('ownerPhone'),
        'designation': ?opt('designation'),
      },
      'expectations': {
        'doctors': int.parse(t('doctors')),
        'staff': int.parse(t('staff')),
        'monthlyPatients': int.parse(t('patients')),
      },
    };
    try {
      final app = await ref
          .read(controlPlaneRepositoryProvider)
          .submitApplication(body);
      if (!mounted) return;
      context.go('/applications/${app['applicationId']}');
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.displayMessage;
        _issues = [for (final i in e.issues) '${i.field}: ${i.message}'];
      });
    }
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? type,
    int max = 200,
    int lines = 1,
    double width = 300,
  }) {
    return SizedBox(
      width: width,
      child: EcTextField(
        label: label,
        controller: _c[key],
        enabled: !_submitting,
        validator: validator,
        keyboardType: type,
        maxLength: max,
        maxLines: lines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget group(String title, List<Widget> children) => Section(
      title: title,
      child: Wrap(
        spacing: EcSpacing.lg,
        runSpacing: EcSpacing.lg,
        children: children,
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Register your clinic',
          subtitle:
              'Tell us about your clinic. A platform administrator reviews every application. Submitting does not give access to any clinic yet.',
          actions: [
            TextButton(
              onPressed: () => context.go('/applications'),
              child: const Text('My applications'),
            ),
          ],
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                EcInlineMessage(
                  message: _issues.isEmpty
                      ? _error!
                      : '$_error ${_issues.join(' · ')}',
                ),
                const SizedBox(height: EcSpacing.lg),
              ],
              group('Clinic', [
                _field(
                  'name',
                  'Clinic name',
                  validator: (v) => _req(v, min: 2, label: 'Clinic name'),
                  max: 120,
                ),
                SizedBox(
                  width: 300,
                  child: EcDropdown<String>(
                    label: 'Clinic type / speciality',
                    items: _clinicTypes,
                    value: _type,
                    itemLabel: Fmt.humanize,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _type = v ?? _type),
                  ),
                ),
                _field(
                  'registrationNumber',
                  'Registration number (if any)',
                  validator: _opt,
                  max: 50,
                ),
                _field(
                  'clinicEmail',
                  'Clinic email',
                  validator: _email,
                  type: TextInputType.emailAddress,
                ),
                _field(
                  'clinicPhone',
                  'Clinic phone',
                  validator: _phone,
                  type: TextInputType.phone,
                ),
                _field(
                  'website',
                  'Website (optional)',
                  validator: _url,
                  type: TextInputType.url,
                ),
                _field(
                  'description',
                  'Description (optional)',
                  validator: _opt,
                  max: 1000,
                  lines: 3,
                  width: 620,
                ),
              ]),
              group('Address', [
                _field(
                  'line1',
                  'Address line 1',
                  validator: (v) => _req(v, min: 3, label: 'Address'),
                  max: 120,
                ),
                _field(
                  'line2',
                  'Address line 2 (optional)',
                  validator: _opt,
                  max: 120,
                ),
                _field(
                  'city',
                  'City',
                  validator: (v) => _req(v, min: 2, label: 'City'),
                  max: 60,
                ),
                _field(
                  'state',
                  'State',
                  validator: (v) => _req(v, min: 2, label: 'State'),
                  max: 60,
                ),
                _field(
                  'country',
                  'Country',
                  validator: (v) => _req(v, min: 2, label: 'Country'),
                  max: 60,
                ),
                _field(
                  'postalCode',
                  'PIN / postal code',
                  validator: _pin,
                  type: TextInputType.number,
                  max: 10,
                ),
              ]),
              group('Owner', [
                _field(
                  'ownerName',
                  'Full name',
                  validator: (v) => _req(v, min: 2, label: 'Name'),
                  max: 80,
                ),
                _field(
                  'ownerEmail',
                  'Email',
                  validator: _email,
                  type: TextInputType.emailAddress,
                ),
                _field(
                  'ownerPhone',
                  'Mobile number',
                  validator: _phone,
                  type: TextInputType.phone,
                ),
                _field(
                  'designation',
                  'Professional designation (optional)',
                  validator: _opt,
                  max: 80,
                ),
              ]),
              group('Expected usage', [
                _field(
                  'doctors',
                  'Number of doctors',
                  validator: _count,
                  type: TextInputType.number,
                  max: 5,
                  width: 200,
                ),
                _field(
                  'staff',
                  'Number of staff',
                  validator: _count,
                  type: TextInputType.number,
                  max: 5,
                  width: 200,
                ),
                _field(
                  'patients',
                  'Patients per month',
                  validator: _count,
                  type: TextInputType.number,
                  max: 7,
                  width: 200,
                ),
              ]),
              const SizedBox(height: EcSpacing.md),
              SizedBox(
                width: 260,
                child: EcPrimaryButton(
                  label: 'Submit application',
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
