import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validation/validation.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'form_kit.dart';
import 'providers.dart';

const clinicTypeChoices = [
  'general_medicine',
  'paediatrics',
  'dentistry',
  'dermatology',
  'gynaecology',
  'physiotherapy',
  'multi_specialty',
  'other',
];

/// Clinic overview: profile summary, logo, what the subscription includes.
class ClinicOverviewPage extends ConsumerWidget {
  const ClinicOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(clinicProfileProvider);
    final ent = ref.watch(entitlementsProvider);
    final logo = ref.watch(clinicLogoProvider).asData?.value;
    final canEdit = can(ref, ClinicPermission.clinicUpdate);
    return AsyncBody(
      value: profile,
      onRetry: () => ref.invalidate(clinicProfileProvider),
      builder: (p) {
        final pr = (p['profile']! as Map<String, Object?>);
        final address = (pr['address'] as Map<String, Object?>?) ?? const {};
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${pr['name']}',
              subtitle: 'Clinic ID ${p['tenantId']}',
              actions: [
                statusChip(p['status']),
                statusChip(p['verificationStatus']),
                if (canEdit)
                  EcPrimaryButton(
                    label: 'Edit profile',
                    compact: true,
                    onPressed: () => context.go('/clinic/profile'),
                  ),
              ],
            ),
            Section(
              title: 'Profile',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (logo != null)
                    Padding(
                      padding: const EdgeInsets.only(right: EcSpacing.lg),
                      child: Image.memory(
                        logo,
                        height: 72,
                        key: const Key('clinic-logo'),
                      ),
                    ),
                  Expanded(
                    child: KeyValues([
                      ('Type', Fmt.humanize(pr['type'])),
                      (
                        'Specialities',
                        ((pr['specialities'] as List?) ?? const []).join(', '),
                      ),
                      ('Registration number', pr['registrationNumber']),
                      ('Email', pr['email']),
                      ('Phone', pr['phone']),
                      ('Alternate phone', pr['alternatePhone']),
                      ('Website', pr['website']),
                      (
                        'Address',
                        [
                          address['line1'],
                          address['line2'],
                          address['city'],
                          address['state'],
                          address['postalCode'],
                          address['country'],
                        ].where((e) => e != null && '$e'.isNotEmpty).join(', '),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            ent.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (e) => Section(
                title: 'Your plan',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyValues([
                      (
                        'Plan',
                        (e['subscription']
                            as Map<String, Object?>?)?['planName'],
                      ),
                      ('Access', statusChip(e['accessLevel'])),
                      for (final l
                          in (e['limits']! as Map<String, Object?>).entries)
                        (Fmt.humanize(l.key), Fmt.limit(l.value)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Profile editor and logo upload.
class ClinicProfileEditPage extends ConsumerStatefulWidget {
  const ClinicProfileEditPage({super.key});

  @override
  ConsumerState<ClinicProfileEditPage> createState() => _ProfileEditState();
}

class _ProfileEditState extends ConsumerState<ClinicProfileEditPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields([
    'name',
    'specialities',
    'registrationNumber',
    'description',
    'email',
    'alternateEmail',
    'phone',
    'alternatePhone',
    'website',
    'line1',
    'line2',
    'city',
    'state',
    'country',
    'postalCode',
  ]);
  String _type = 'general_medicine';
  bool _loaded = false;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _fill(Json p) {
    final pr = (p['profile']! as Map<String, Object?>);
    final a = (pr['address'] as Map<String, Object?>?) ?? const {};
    _f
      ..set('name', pr['name'])
      ..set(
        'specialities',
        ((pr['specialities'] as List?) ?? const []).join(', '),
      )
      ..set('registrationNumber', pr['registrationNumber'])
      ..set('description', pr['description'])
      ..set('email', pr['email'])
      ..set('alternateEmail', pr['alternateEmail'])
      ..set('phone', pr['phone'])
      ..set('alternatePhone', pr['alternatePhone'])
      ..set('website', pr['website'])
      ..set('line1', a['line1'])
      ..set('line2', a['line2'])
      ..set('city', a['city'])
      ..set('state', a['state'])
      ..set('country', a['country'])
      ..set('postalCode', a['postalCode']);
    _type = clinicTypeChoices.contains(pr['type'])
        ? pr['type']! as String
        : _type;
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    final body = <String, Object?>{
      'name': _f.text('name'),
      'type': _type,
      'specialities': _f.text('specialities').isEmpty
          ? <String>[]
          : _f
                .text('specialities')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
      'registrationNumber': ?_f.opt('registrationNumber'),
      'description': ?_f.opt('description'),
      'email': _f.text('email'),
      'alternateEmail': ?_f.opt('alternateEmail'),
      'phone': _f.text('phone'),
      'alternatePhone': ?_f.opt('alternatePhone'),
      'website': ?_f.opt('website'),
      'address': {
        'line1': _f.text('line1'),
        'line2': ?_f.opt('line2'),
        'city': _f.text('city'),
        'state': _f.text('state'),
        'country': _f.text('country'),
        'postalCode': _f.text('postalCode'),
      },
    };
    try {
      await ref
          .read(controlPlaneRepositoryProvider)
          .sendMap('PATCH', '/clinics/current', body);
      ref.invalidate(clinicProfileProvider);
      if (mounted) context.go('/clinic');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureText(e);
        });
      }
    }
  }

  Future<void> _uploadLogo() async {
    final picked = await ref.read(logoPickerProvider)();
    if (picked == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(controlPlaneRepositoryProvider).sendMap(
        'PUT',
        '/clinics/current/logo',
        {
          'contentType': picked.contentType,
          'dataBase64': base64Encode(picked.bytes),
        },
      );
      ref.invalidate(clinicLogoProvider);
      ref.invalidate(clinicProfileProvider);
      if (mounted) {
        setState(() {
          _uploading = false;
          _notice = 'Logo updated.';
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = failureText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return AsyncBody(
        value: ref.watch(clinicProfileProvider),
        onRetry: () => ref.invalidate(clinicProfileProvider),
        builder: (p) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(p));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    final logo = ref.watch(clinicLogoProvider).asData?.value;
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Edit clinic profile',
          subtitle:
              'Identity, ownership and verification status cannot be edited here.',
        ),
        if (_error != null) ...[
          EcInlineMessage(message: _error!),
          const SizedBox(height: EcSpacing.lg),
        ],
        if (_notice != null) ...[
          EcInlineMessage(message: _notice!, tone: EcStatusTone.success),
          const SizedBox(height: EcSpacing.lg),
        ],
        Section(
          title: 'Logo',
          child: Row(
            children: [
              if (logo != null)
                Padding(
                  padding: const EdgeInsets.only(right: EcSpacing.lg),
                  child: Image.memory(
                    logo,
                    height: 64,
                    key: const Key('clinic-logo'),
                  ),
                ),
              EcSecondaryButton(
                label: logo == null ? 'Upload logo' : 'Change logo',
                icon: Icons.upload_outlined,
                compact: true,
                isLoading: _uploading,
                onPressed: _uploadLogo,
              ),
              const SizedBox(width: EcSpacing.md),
              Flexible(
                child: Text(
                  'PNG, JPEG or WebP, up to 512 KB.',
                  style: EcTypography.helper,
                ),
              ),
            ],
          ),
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Section(
                title: 'Clinic',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Clinic name',
                      controller: _f['name'],
                      validator: (v) =>
                          requiredText(v, min: 2, label: 'Clinic name'),
                      maxLength: 120,
                    ),
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Type',
                        items: clinicTypeChoices,
                        value: _type,
                        itemLabel: Fmt.humanize,
                        onChanged: (v) => setState(() => _type = v ?? _type),
                      ),
                    ),
                    TextRow(
                      label: 'Specialities (comma separated)',
                      controller: _f['specialities'],
                      width: 620,
                      maxLength: 400,
                    ),
                    TextRow(
                      label: 'Registration number',
                      controller: _f['registrationNumber'],
                      maxLength: 50,
                    ),
                    TextRow(label: 'Website', controller: _f['website']),
                    TextRow(
                      label: 'Description',
                      controller: _f['description'],
                      width: 620,
                      lines: 3,
                      maxLength: 1000,
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
                      label: 'Email',
                      controller: _f['email'],
                      validator: (v) => Validators.email(v)?.message,
                    ),
                    TextRow(
                      label: 'Alternate email',
                      controller: _f['alternateEmail'],
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.email(v)?.message,
                    ),
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
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'State',
                      controller: _f['state'],
                      validator: (v) => requiredText(v, min: 2, label: 'State'),
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'Country',
                      controller: _f['country'],
                      validator: (v) =>
                          requiredText(v, min: 2, label: 'Country'),
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'PIN / postal code',
                      controller: _f['postalCode'],
                      validator: (v) =>
                          requiredText(v, min: 3, label: 'PIN code'),
                      maxLength: 10,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: EcPrimaryButton(
                      label: 'Save changes',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving ? null : () => context.go('/clinic'),
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
}
