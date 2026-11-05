import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clinic_admin/providers.dart' show can;
import '../control_plane/data/control_plane_repository.dart';
import '../laboratory/lab_pages.dart' show reportSaverProvider;
import '../patients/patient_providers.dart'
    show PickedDocument, documentPickerProvider;
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'compliance_labels.dart';
import 'compliance_providers.dart';

/// A clinic's compliance checklist, evidence and credentials.
///
/// It organises evidence. It never says the clinic "is compliant": a
/// platform reviewer approves evidence, and the registers are working drafts
/// until counsel has validated them.
class CompliancePage extends ConsumerWidget {
  const CompliancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = can(ref, ClinicPermission.complianceManage);
    void reload() {
      ref.invalidate(complianceDashboardProvider);
      ref.invalidate(complianceCredentialsProvider);
    }

    return AsyncBody<Json>(
      value: ref.watch(complianceDashboardProvider),
      onRetry: reload,
      builder: (d) {
        final profiles = (d['profiles']! as List).cast<Json>();
        final credentials = (d['credentials']! as Map).cast<String, Object?>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Compliance',
              subtitle:
                  'Evidence for the registers that apply to your clinic. A platform reviewer approves evidence.',
            ),
            EcInlineMessage(
              message: '${d['disclaimer']}',
              tone: EcStatusTone.info,
            ),
            const SizedBox(height: EcSpacing.md),
            Row(
              children: [
                EcStatusChip(
                  label: 'Status',
                  tone: readinessTone(d['readiness']),
                ),
                const SizedBox(width: EcSpacing.sm),
                Expanded(
                  child: Text(
                    readinessLabel(d['readiness']),
                    key: const Key('readiness-text'),
                    style: EcTypography.body,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EcSpacing.lg),
            if (profiles.isEmpty)
              const EcEmptyState(
                title: 'No registers for your country yet',
                message: 'Registers appear here once your country has them.',
                icon: Icons.fact_check_outlined,
              ),
            for (final p in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.md),
                child: _ProfileCard(
                  profile: p,
                  canManage: canManage,
                  onChanged: reload,
                ),
              ),
            _CredentialsSection(
              summary: credentials,
              canManage: canManage,
              onChanged: reload,
            ),
          ],
        );
      },
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({
    required this.profile,
    required this.canManage,
    required this.onChanged,
  });

  final Json profile;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final applicability = (p['applicability']! as Map)['status'];
    final reviewed = (p['legalReview']! as Map)['status'] == 'reviewed';
    final reqs = (p['requirements']! as List).cast<Json>();
    return EcCard(
      key: Key('profile-${p['key']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${p['title']}', style: EcTypography.subsectionTitle),
              EcStatusChip(label: 'Version ${p['version']}'),
              EcStatusChip(
                label: reviewed
                    ? 'Validated by counsel'
                    : 'Not validated by counsel',
                tone: reviewed ? EcStatusTone.success : EcStatusTone.warning,
              ),
              EcStatusChip(
                label: applicability == 'applies'
                    ? 'Applies to your clinic'
                    : applicability == 'not_applicable'
                    ? 'Does not apply'
                    : 'Applicability not confirmed',
                tone: applicability == 'applies'
                    ? EcStatusTone.info
                    : EcStatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: EcSpacing.xs),
          Text(
            '${(p['authority']! as Map)['name']}',
            style: EcTypography.bodySecondary,
          ),
          const SizedBox(height: EcSpacing.xs),
          Text('${p['appliesWhenNote']}', style: EcTypography.helper),
          if (applicability != 'applies') ...[
            const SizedBox(height: EcSpacing.md),
            Text(
              applicability == 'not_applicable'
                  ? 'A reviewer has recorded that this register does not apply.'
                  : 'A reviewer must confirm that this register applies before you can add evidence.',
              style: EcTypography.body,
            ),
          ] else ...[
            const SizedBox(height: EcSpacing.md),
            for (final r in reqs)
              _RequirementRow(
                profileKey: '${p['key']}',
                requirement: r,
                canManage: canManage,
                onChanged: onChanged,
              ),
          ],
        ],
      ),
    );
  }
}

class _RequirementRow extends ConsumerWidget {
  const _RequirementRow({
    required this.profileKey,
    required this.requirement,
    required this.canManage,
    required this.onChanged,
  });

  final String profileKey;
  final Json requirement;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = requirement;
    final status = '${r['status']}';
    final ev = (r['evidence']! as Map).cast<String, Object?>();
    final canUpload =
        canManage && ev['required'] == true && status != 'not_applicable';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EcSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${r['title']}', style: EcTypography.bodyStrong),
              EcStatusChip(
                key: Key('status-${r['key']}'),
                label: complianceStatusLabel(status),
                tone: complianceStatusTone(status),
              ),
              EcStatusChip(label: humanizeKey(r['category'])),
              if (r['goLiveBlocking'] == true)
                const EcStatusChip(label: 'Needed before go-live'),
            ],
          ),
          Text('${r['description']}', style: EcTypography.helper),
          if (r['expiresAt'] != null)
            Text(
              status == 'expired'
                  ? 'Expired on ${Fmt.date(r['expiresAt'])}'
                  : 'Approval valid until ${Fmt.date(r['expiresAt'])}',
              style: EcTypography.helper,
            ),
          if (r['requirementChanged'] == true)
            const Text(
              'This requirement changed after it was approved. New evidence is needed.',
            ),
          if (r['note'] != null && '${r['note']}'.isNotEmpty)
            Text('Reviewer note: ${r['note']}', style: EcTypography.helper),
          const SizedBox(height: EcSpacing.xs),
          Wrap(
            spacing: EcSpacing.sm,
            children: [
              if (canUpload)
                EcSecondaryButton(
                  key: Key('upload-${r['key']}'),
                  label: r['evidenceId'] == null
                      ? 'Upload evidence'
                      : 'Upload new evidence',
                  compact: true,
                  onPressed: () => _upload(context, ref),
                ),
              if (r['evidenceId'] != null)
                EcSecondaryButton(
                  key: Key('view-${r['key']}'),
                  label: 'Download file',
                  compact: true,
                  onPressed: () => runAction(
                    context,
                    action: () async {
                      final bytes = await ref
                          .read(controlPlaneRepositoryProvider)
                          .complianceEvidenceBytes('${r['evidenceId']}');
                      await ref.read(reportSaverProvider)(
                        'evidence-${r['evidenceId']}',
                        bytes,
                      );
                    },
                    success: 'File downloaded.',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final ev = (requirement['evidence']! as Map).cast<String, Object?>();
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => _EvidenceDialog(
        requirementTitle: '${requirement['title']}',
        kinds: (ev['kinds']! as List).cast<String>(),
        expiryTracked: ev['expiryTracked'] == true,
      ),
    );
    if (result == null || !context.mounted) return;
    await runAction(
      context,
      action: () =>
          ref.read(controlPlaneRepositoryProvider).uploadComplianceEvidence({
            'profileKey': profileKey,
            'requirementKey': requirement['key'],
            ...result,
          }),
      success: 'Evidence submitted for review.',
      after: onChanged,
    );
  }
}

/// Collects the details of one evidence file and lets the user pick it.
class _EvidenceDialog extends ConsumerStatefulWidget {
  const _EvidenceDialog({
    required this.requirementTitle,
    required this.kinds,
    required this.expiryTracked,
  });

  final String requirementTitle;
  final List<String> kinds;
  final bool expiryTracked;

  @override
  ConsumerState<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends ConsumerState<_EvidenceDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _number = TextEditingController();
  final _validTo = TextEditingController();
  late String _kind = widget.kinds.isEmpty ? 'other' : widget.kinds.first;
  PickedDocument? _file;
  String? _fileError;

  @override
  void dispose() {
    _title.dispose();
    _number.dispose();
    _validTo.dispose();
    super.dispose();
  }

  String? _date(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) {
      return widget.expiryTracked ? 'Enter the expiry date.' : null;
    }
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t) &&
            DateTime.tryParse(t) != null
        ? null
        : 'Use the format 2027-03-31.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload evidence'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.requirementTitle,
                  style: EcTypography.bodySecondary,
                ),
                const SizedBox(height: EcSpacing.md),
                EcDropdown<String>(
                  label: 'Document type',
                  items: widget.kinds.isEmpty ? const ['other'] : widget.kinds,
                  value: _kind,
                  itemLabel: humanizeKey,
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Title',
                  controller: _title,
                  validator: (v) =>
                      (v ?? '').trim().length < 3 ? 'Enter a title.' : null,
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Document number (optional)',
                  controller: _number,
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: widget.expiryTracked
                      ? 'Valid until (YYYY-MM-DD)'
                      : 'Valid until (optional, YYYY-MM-DD)',
                  controller: _validTo,
                  validator: _date,
                ),
                const SizedBox(height: EcSpacing.md),
                Row(
                  children: [
                    // a button's minimum width is unbounded, so give it one
                    SizedBox(
                      width: 150,
                      child: EcSecondaryButton(
                        label: _file == null ? 'Choose file' : 'Change file',
                        compact: true,
                        onPressed: () async {
                          final f = await ref.read(documentPickerProvider)();
                          if (f != null) {
                            setState(() {
                              _file = f;
                              _fileError = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: EcSpacing.sm),
                    Expanded(
                      child: Text(
                        _file?.name ?? 'PDF, PNG or JPEG, up to 3 MB',
                      ),
                    ),
                  ],
                ),
                if (_fileError != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_fileError!, style: EcTypography.error),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final ok = _form.currentState!.validate();
            if (_file == null) setState(() => _fileError = 'Choose a file.');
            if (!ok || _file == null) return;
            Navigator.of(context).pop({
              'kind': _kind,
              'title': _title.text.trim(),
              if (_number.text.trim().isNotEmpty)
                'documentNumber': _number.text.trim(),
              if (_validTo.text.trim().isNotEmpty)
                'validTo': _validTo.text.trim(),
              'contentType': _file!.contentType,
              'dataBase64': base64Encode(_file!.bytes),
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _CredentialsSection extends ConsumerWidget {
  const _CredentialsSection({
    required this.summary,
    required this.canManage,
    required this.onChanged,
  });

  final Map<String, Object?> summary;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(complianceCredentialsProvider);
    return Section(
      title: 'Credentials and licences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            children: [
              EcStatusChip(
                label: 'Valid: ${summary['valid']}',
                tone: EcStatusTone.success,
              ),
              EcStatusChip(
                label: 'Expiring soon: ${summary['expiring']}',
                tone: EcStatusTone.warning,
              ),
              EcStatusChip(
                label: 'Expired: ${summary['expired']}',
                tone: EcStatusTone.error,
              ),
              EcStatusChip(label: 'Not verified: ${summary['unverified']}'),
            ],
          ),
          const SizedBox(height: EcSpacing.md),
          if (canManage)
            EcSecondaryButton(
              key: const Key('add-credential'),
              label: 'Add credential',
              compact: true,
              icon: Icons.add,
              onPressed: () async {
                final body = await showDialog<Json>(
                  context: context,
                  builder: (_) => const _CredentialDialog(),
                );
                if (body == null || !context.mounted) return;
                await runAction(
                  context,
                  action: () => ref
                      .read(controlPlaneRepositoryProvider)
                      .createComplianceCredential(body),
                  success: 'Credential saved.',
                  after: onChanged,
                );
              },
            ),
          const SizedBox(height: EcSpacing.md),
          list.when(
            loading: () => const EcLoadingIndicator(),
            error: (e, _) => EcErrorState(
              onRetry: () => ref.invalidate(complianceCredentialsProvider),
            ),
            data: (items) => items.isEmpty
                ? const Text('No credentials recorded yet.')
                : Column(
                    children: [
                      for (final c in items)
                        _CredentialRow(
                          credential: c,
                          canManage: canManage,
                          onChanged: onChanged,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CredentialRow extends ConsumerWidget {
  const _CredentialRow({
    required this.credential,
    required this.canManage,
    required this.onChanged,
  });

  final Json credential;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = credential;
    final verification = (c['verification'] as Map?)?['status'];
    return Padding(
      key: Key('credential-${c['credentialId']}'),
      padding: const EdgeInsets.symmetric(vertical: EcSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${c['subjectName']}', style: EcTypography.bodyStrong),
              EcStatusChip(label: humanizeKey(c['kind'])),
              EcStatusChip(
                label: validityLabel(c['validity']),
                tone: validityTone(c['validity']),
              ),
              EcStatusChip(
                label: verificationLabel(verification),
                tone: verificationTone(verification),
              ),
            ],
          ),
          Text(
            '${c['authorityName']} · No. ${c['number']}'
            '${c['validTo'] != null ? ' · valid until ${Fmt.date(c['validTo'])}' : ''}',
            style: EcTypography.helper,
          ),
          if (canManage)
            Wrap(
              spacing: EcSpacing.sm,
              children: [
                EcSecondaryButton(
                  label: 'Attach document',
                  compact: true,
                  onPressed: () async {
                    final f = await ref.read(documentPickerProvider)();
                    if (f == null || !context.mounted) return;
                    await runAction(
                      context,
                      action: () => ref
                          .read(controlPlaneRepositoryProvider)
                          .attachCredentialDocument('${c['credentialId']}', {
                            'contentType': f.contentType,
                            'dataBase64': base64Encode(f.bytes),
                          }),
                      success: 'Document submitted for review.',
                      after: onChanged,
                    );
                  },
                ),
                EcSecondaryButton(
                  label: 'Archive',
                  compact: true,
                  onPressed: () async {
                    final ok = await showEcConfirmDialog(
                      context,
                      title: 'Archive this credential?',
                      message:
                          'It will no longer be tracked or raise expiry alerts.',
                      confirmLabel: 'Archive',
                    );
                    if (!ok || !context.mounted) return;
                    await runAction(
                      context,
                      action: () => ref
                          .read(controlPlaneRepositoryProvider)
                          .archiveComplianceCredential('${c['credentialId']}'),
                      success: 'Credential archived.',
                      after: onChanged,
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog();

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'subjectName',
      'authorityCode',
      'authorityName',
      'number',
      'validTo',
    ])
      k: TextEditingController(),
  };
  String _type = 'facility';
  String _kind = 'facility_license';

  static const _facilityKinds = [
    'facility_license',
    'facility_registration',
    'other',
  ];
  static const _practitionerKinds = [
    'practitioner_registration',
    'practitioner_license',
    'other',
  ];

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v, String label) =>
      (v ?? '').trim().length < 2 ? 'Enter $label.' : null;

  @override
  Widget build(BuildContext context) {
    final kinds = _type == 'facility' ? _facilityKinds : _practitionerKinds;
    return AlertDialog(
      title: const Text('Add credential'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EcDropdown<String>(
                  label: 'Applies to',
                  items: const ['facility', 'practitioner'],
                  value: _type,
                  itemLabel: humanizeKey,
                  onChanged: (v) => setState(() {
                    _type = v ?? _type;
                    _kind =
                        (_type == 'facility'
                                ? _facilityKinds
                                : _practitionerKinds)
                            .first;
                  }),
                ),
                const SizedBox(height: EcSpacing.md),
                EcDropdown<String>(
                  label: 'Type',
                  items: kinds,
                  value: kinds.contains(_kind) ? _kind : kinds.first,
                  itemLabel: humanizeKey,
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: _type == 'facility'
                      ? 'Facility name'
                      : 'Practitioner name',
                  controller: _c['subjectName'],
                  validator: (v) => _req(v, 'a name'),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Authority code (e.g. DHA, NMC)',
                  controller: _c['authorityCode'],
                  validator: (v) => _req(v, 'the authority code'),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Issuing authority',
                  controller: _c['authorityName'],
                  validator: (v) => _req(v, 'the authority name'),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Licence or registration number',
                  controller: _c['number'],
                  validator: (v) => _req(v, 'the number'),
                ),
                const SizedBox(height: EcSpacing.md),
                EcTextField(
                  label: 'Valid until (YYYY-MM-DD)',
                  controller: _c['validTo'],
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t) &&
                            DateTime.tryParse(t) != null
                        ? null
                        : 'Use the format 2027-03-31.';
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            String t(String k) => _c[k]!.text.trim();
            Navigator.of(context).pop({
              'subjectType': _type,
              'subjectName': t('subjectName'),
              'kind': _kind,
              'authorityCode': t('authorityCode'),
              'authorityName': t('authorityName'),
              'number': t('number'),
              if (t('validTo').isNotEmpty) 'validTo': t('validTo'),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
