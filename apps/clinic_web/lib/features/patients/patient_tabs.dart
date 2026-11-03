import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart' show failureText;
import '../shared/paged_list.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'dialogs.dart';
import 'patient_providers.dart';

const _sources = [
  'patient_reported',
  'caregiver_reported',
  'clinic_recorded',
  'imported',
];

/// Source and verification, always visible so patient-reported information is
/// never mistaken for clinician-verified information.
Widget provenance(Map<String, Object?> r) => Wrap(
  spacing: EcSpacing.xs,
  children: [
    EcStatusChip(
      label: 'Source: ${Fmt.humanize(r['source'])}',
      tone: EcStatusTone.info,
    ),
    EcStatusChip(
      label: r['verificationStatus'] == 'verified'
          ? 'Verified by clinician'
          : 'Unverified',
      tone: r['verificationStatus'] == 'verified'
          ? EcStatusTone.success
          : EcStatusTone.warning,
    ),
  ],
);

/// List + add + edit for one kind of clinic-recorded information.
class RecordTab extends ConsumerWidget {
  const RecordTab({
    required this.patientId,
    required this.segment,
    required this.noun,
    required this.fields,
    required this.manage,
    required this.title,
    required this.subtitle,
    this.extraNote,
    this.filterParam,
    this.filterOptions = const [],
    super.key,
  });

  final String patientId;

  /// `medical-history`, `allergies`, `medications` or `alerts`.
  final String segment;
  final String noun;
  final List<FieldSpec> fields;
  final String manage;
  final String Function(Map<String, Object?>) title;
  final String Function(Map<String, Object?>) subtitle;
  final String? extraNote;
  final String? filterParam;
  final List<String> filterOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = '/patients/$patientId/$segment';
    final query = ListQuery(path);
    final state = ref.watch(pagedListProvider(query));
    final canManage = can(ref, manage);
    final isDoctor =
        ref.watch(clinicAccessProvider).asData?.value['role'] == 'doctor';
    final repo = ref.read(controlPlaneRepositoryProvider);
    void reload() {
      ref.invalidate(pagedListProvider(query));
      ref.invalidate(patientDetailProvider(patientId));
    }

    Future<void> add() async {
      final r = await showRecordDialog(
        context,
        title: 'Add $noun',
        fields: [
          ...fields,
          const FieldSpec(
            'source',
            'Where does this come from?',
            kind: FieldKind.choice,
            options: _sources,
          ),
        ],
        note: extraNote,
      );
      if (r == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.sendMap('POST', path, r),
        success: '${noun[0].toUpperCase()}${noun.substring(1)} added.',
        after: reload,
      );
    }

    Future<void> edit(Map<String, Object?> item, String id) async {
      final r = await showRecordDialog(
        context,
        title: 'Update $noun',
        fields: fields,
        initial: item,
        note:
            'Changing this clears its clinician verification. The previous version is kept.',
      );
      if (r == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.sendMap('PATCH', '$path/$id', {
          for (final e in r.entries)
            if (fields.firstWhere((f) => f.key == e.key).editable)
              e.key: e.value,
        }),
        success: 'Updated.',
        after: reload,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        _Toolbar(
          text: subtitle({}),
          action: canManage
              ? EcPrimaryButton(
                  label: 'Add $noun',
                  icon: Icons.add,
                  compact: true,
                  onPressed: add,
                )
              : null,
        ),
        const SizedBox(height: EcSpacing.md),
        if (state.loading)
          const EcLoadingIndicator()
        else if (state.error != null)
          EcErrorState(
            title: 'Could not load this information',
            message: state.error!.displayMessage,
            onRetry: () => ref.invalidate(pagedListProvider(query)),
          )
        else if (state.items.isEmpty)
          EcEmptyState(
            title: 'Nothing recorded yet',
            message:
                'No $noun has been recorded. This does not confirm that there is none.',
          )
        else
          for (final item in state.items)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.sm),
              child: EcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title(item),
                            style: EcTypography.bodyStrong,
                          ),
                        ),
                        if (item['status'] != null) statusChip(item['status']),
                      ],
                    ),
                    Text(subtitle(item), style: EcTypography.bodySecondary),
                    const SizedBox(height: EcSpacing.xs),
                    provenance(item),
                    if (canManage)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () =>
                                edit(item, '${item[_idKey(segment)]}'),
                            child: const Text('Edit'),
                          ),
                          if (isDoctor &&
                              item['verificationStatus'] != 'verified')
                            TextButton(
                              onPressed: () => runAction(
                                context,
                                action: () => repo.sendMap(
                                  'PATCH',
                                  '$path/${item[_idKey(segment)]}',
                                  {'verify': true},
                                ),
                                success: 'Marked as verified.',
                                after: reload,
                              ),
                              child: const Text('Mark as verified'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        if (state.hasMore)
          Center(
            child: EcSecondaryButton(
              label: 'Load more',
              compact: true,
              onPressed: () =>
                  ref.read(pagedListProvider(query).notifier).loadMore(),
            ),
          ),
      ],
    );
  }

  static String _idKey(String segment) => switch (segment) {
    'medical-history' => 'entryId',
    'allergies' => 'allergyId',
    'medications' => 'medicationId',
    _ => 'alertId',
  };
}

class HistoryTab extends StatelessWidget {
  const HistoryTab({required this.patientId, super.key});
  final String patientId;

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) => RecordTab(
      patientId: patientId,
      segment: 'medical-history',
      noun: 'history entry',
      manage: ClinicPermission.historyManage,
      fields: const [
        FieldSpec(
          'category',
          'Category',
          kind: FieldKind.choice,
          required: true,
          editable: false,
          options: [
            'condition',
            'chronic_condition',
            'previous_illness',
            'surgery',
            'hospitalization',
            'family_history',
            'immunization',
            'lifestyle',
          ],
        ),
        FieldSpec('title', 'Condition / procedure / vaccine', required: true),
        FieldSpec(
          'status',
          'Status',
          kind: FieldKind.choice,
          options: ['active', 'resolved', 'inactive', 'entered_in_error'],
        ),
        FieldSpec('relative', 'Relative (family history)'),
        FieldSpec('onsetDate', 'Onset date', kind: FieldKind.date),
        FieldSpec('resolvedDate', 'Resolved date', kind: FieldKind.date),
        FieldSpec(
          'eventDate',
          'Procedure / vaccination date',
          kind: FieldKind.date,
        ),
        FieldSpec('provider', 'Hospital / surgeon / provider'),
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline, maxLength: 1000),
      ],
      title: (r) => '${r['title']}',
      subtitle: (r) => r.isEmpty
          ? 'Conditions, surgeries, hospital stays, family and immunization history.'
          : '${Fmt.humanize(r['category'])}${r['relative'] == null ? '' : ' · ${r['relative']}'}${r['onsetDate'] == null ? '' : ' · since ${r['onsetDate']}'}',
    ),
  );
}

class AllergiesTab extends StatelessWidget {
  const AllergiesTab({required this.patientId, super.key});
  final String patientId;

  @override
  Widget build(BuildContext context) => RecordTab(
    patientId: patientId,
    segment: 'allergies',
    noun: 'allergy',
    manage: ClinicPermission.allergiesManage,
    extraNote: 'New allergies stay "unverified" until a doctor verifies them.',
    fields: const [
      FieldSpec('allergen', 'Allergen', required: true),
      FieldSpec(
        'category',
        'Category',
        kind: FieldKind.choice,
        required: true,
        options: ['drug', 'food', 'environmental', 'insect', 'latex', 'other'],
      ),
      FieldSpec('reaction', 'Reaction'),
      FieldSpec(
        'severity',
        'Severity',
        kind: FieldKind.choice,
        options: ['mild', 'moderate', 'severe', 'unknown'],
      ),
      FieldSpec('onsetDate', 'Onset date', kind: FieldKind.date),
      FieldSpec(
        'status',
        'Status',
        kind: FieldKind.choice,
        options: ['active', 'inactive', 'unverified'],
      ),
      FieldSpec('notes', 'Notes', kind: FieldKind.multiline, maxLength: 1000),
    ],
    title: (r) => '${r['allergen']}',
    subtitle: (r) => r.isEmpty
        ? 'Absence of a record does not mean no known allergies.'
        : '${Fmt.humanize(r['category'])} · severity ${Fmt.humanize(r['severity'])}${r['reaction'] == null ? '' : ' · ${r['reaction']}'}',
  );
}

class MedicationsTab extends StatelessWidget {
  const MedicationsTab({required this.patientId, super.key});
  final String patientId;

  @override
  Widget build(BuildContext context) => RecordTab(
    patientId: patientId,
    segment: 'medications',
    noun: 'medication',
    manage: ClinicPermission.medicationsManage,
    extraNote:
        'This is a history of medicines, not a prescription. Prescribing comes later.',
    fields: const [
      FieldSpec('name', 'Medicine', required: true),
      FieldSpec('genericName', 'Generic name'),
      FieldSpec('strength', 'Strength', maxLength: 40),
      FieldSpec('dosage', 'Dosage', maxLength: 60),
      FieldSpec('route', 'Route', maxLength: 30),
      FieldSpec('frequency', 'Frequency', maxLength: 60),
      FieldSpec('startDate', 'Start date', kind: FieldKind.date),
      FieldSpec('endDate', 'End date', kind: FieldKind.date),
      FieldSpec(
        'status',
        'Status',
        kind: FieldKind.choice,
        options: ['current', 'completed', 'discontinued', 'unknown'],
      ),
      FieldSpec('prescriber', 'Prescribed by'),
      FieldSpec('notes', 'Notes', kind: FieldKind.multiline, maxLength: 1000),
    ],
    title: (r) => '${r['name']}',
    subtitle: (r) => r.isEmpty
        ? 'Medicines the patient has taken or is taking, as reported or recorded.'
        : [
            r['strength'],
            r['dosage'],
            r['frequency'],
          ].where((e) => e != null).join(' · '),
  );
}

class AlertsTab extends StatelessWidget {
  const AlertsTab({required this.patientId, super.key});
  final String patientId;

  @override
  Widget build(BuildContext context) => RecordTab(
    patientId: patientId,
    segment: 'alerts',
    noun: 'alert',
    manage: ClinicPermission.alertsManage,
    extraNote:
        'Medical and allergy alerts can only be created by clinical staff.',
    fields: const [
      FieldSpec(
        'category',
        'Category',
        kind: FieldKind.choice,
        required: true,
        editable: false,
        options: [
          'medical',
          'allergy',
          'special_assistance',
          'communication',
          'administrative',
          'other',
        ],
      ),
      FieldSpec('title', 'Title', required: true, maxLength: 100),
      FieldSpec(
        'message',
        'Message',
        required: true,
        kind: FieldKind.multiline,
        maxLength: 500,
      ),
      FieldSpec(
        'priority',
        'Priority',
        kind: FieldKind.choice,
        options: ['info', 'warning', 'critical'],
      ),
      FieldSpec(
        'status',
        'Status',
        kind: FieldKind.choice,
        options: ['active', 'resolved'],
      ),
    ],
    title: (r) => '${r['title']}',
    subtitle: (r) => r.isEmpty
        ? 'Important information shown at the top of the patient record.'
        : '${Fmt.humanize(r['category'])} · ${Fmt.humanize(r['priority'])} · ${r['message']}',
  );
}

// ---------------------------------------------------------------- consent

class ConsentTab extends ConsumerWidget {
  const ConsentTab({required this.patient, super.key});

  final Json patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${patient['patientId']}';
    final query = ListQuery('/patients/$id/consents');
    final state = ref.watch(pagedListProvider(query));
    final catalog = ref.watch(consentCatalogProvider).asData?.value;
    final repo = ref.read(controlPlaneRepositoryProvider);
    final purposes = ((catalog?['purposes'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final guardian = patient['guardian'] as Map<String, Object?>?;
    final guardianVerified = guardian != null && guardian['verified'] == true;
    final canManage =
        can(ref, ClinicPermission.consentsManage) &&
        patient['status'] != 'archived';
    void reload() => ref.invalidate(pagedListProvider(query));

    Future<void> record() async {
      if (catalog == null) return;
      final r = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => _ConsentDialog(
          purposes: purposes,
          guardianVerified: guardianVerified,
        ),
      );
      if (r == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.sendMap('POST', '/patients/$id/consents', {
          'type': r['type'],
          'decision': r['decision'],
          'textVersion': catalog['version'],
          'collectionMethod': r['method'],
          'grantedBy': r['by'],
          'purpose': ?r['purpose'],
        }),
        success: 'Consent recorded.',
        after: reload,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        _Toolbar(
          text:
              'Each consent is specific, recorded with who gave it, and can be withdrawn at any time.',
          action: canManage
              ? EcPrimaryButton(
                  label: 'Record consent',
                  icon: Icons.add,
                  compact: true,
                  onPressed: record,
                )
              : null,
        ),
        const SizedBox(height: EcSpacing.md),
        if (state.loading)
          const EcLoadingIndicator()
        else if (state.error != null)
          EcErrorState(
            title: 'Could not load consents',
            message: state.error!.displayMessage,
            onRetry: reload,
          )
        else if (state.items.isEmpty)
          const EcEmptyState(
            title: 'No consent recorded',
            message: 'Nothing is assumed from silence.',
          )
        else
          for (final c in state.items)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.sm),
              child: EcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Fmt.humanize(c['type']),
                            style: EcTypography.bodyStrong,
                          ),
                        ),
                        statusChip(c['status']),
                      ],
                    ),
                    Text('${c['purpose']}', style: EcTypography.bodySecondary),
                    Text(
                      'Decided ${Fmt.dateTime(c['decidedAt'])} · by ${Fmt.humanize((c['grantedBy'] as Map?)?['type'])} · ${Fmt.humanize(c['collectionMethod'])} · text v${c['textVersion']}',
                      style: EcTypography.helper,
                    ),
                    if (c['revokedAt'] != null)
                      Text(
                        'Revoked ${Fmt.dateTime(c['revokedAt'])}: ${c['revokeReason']}',
                        style: EcTypography.helper,
                      ),
                    if (c['status'] == 'granted' && canManage)
                      TextButton(
                        onPressed: () async {
                          final reason = await askReason(
                            context,
                            title: 'Revoke consent?',
                            message:
                                'New processing that depends on this consent stops. The original record is kept as evidence.',
                            confirmLabel: 'Revoke',
                          );
                          if (reason == null || !context.mounted) return;
                          await runAction(
                            context,
                            action: () => repo.sendMap(
                              'POST',
                              '/patients/$id/consents/${c['consentId']}/revoke',
                              {
                                'reason': reason,
                                if (_grantorOf(c) == 'guardian')
                                  'requestedBy': {
                                    'type': 'guardian',
                                    'name': guardian?['name'],
                                    'relationship': guardian?['relationship'],
                                  },
                              },
                            ),
                            success: 'Consent revoked.',
                            after: reload,
                          );
                        },
                        child: const Text('Revoke'),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String? _grantorOf(Map<String, Object?> c) =>
      (c['grantedBy'] as Map?)?['type'] as String?;
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({
    required this.purposes,
    required this.guardianVerified,
  });

  final List<Map<String, Object?>> purposes;
  final bool guardianVerified;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  late Map<String, Object?> _purpose = widget.purposes.first;
  String? _decision;
  String _method = 'in_person_signed';
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record consent'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EcDropdown<String>(
              label: 'Purpose',
              items: [for (final p in widget.purposes) '${p['type']}'],
              value: '${_purpose['type']}',
              itemLabel: Fmt.humanize,
              onChanged: (v) => setState(() {
                _purpose = widget.purposes.firstWhere((p) => p['type'] == v);
              }),
            ),
            const SizedBox(height: EcSpacing.md),
            Text(
              '${_purpose['text']}',
              key: const Key('consent-dialog-text'),
              style: EcTypography.body,
            ),
            if (_purpose['type'] == 'other') ...[
              const SizedBox(height: EcSpacing.md),
              EcTextField(
                label: 'Describe the purpose',
                controller: _custom,
                maxLength: 200,
              ),
            ],
            const SizedBox(height: EcSpacing.md),
            EcDropdown<String>(
              label: 'The decision',
              items: const ['granted', 'rejected'],
              value: _decision,
              itemLabel: (v) => v == 'granted' ? 'Agreed' : 'Declined',
              onChanged: (v) => setState(() => _decision = v),
            ),
            const SizedBox(height: EcSpacing.md),
            EcDropdown<String>(
              label: 'How was it given?',
              items: const [
                'in_person_signed',
                'in_person_verbal',
                'digital_form',
                'phone_recorded',
              ],
              value: _method,
              itemLabel: Fmt.humanize,
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            if (widget.guardianVerified)
              Padding(
                padding: EdgeInsets.only(top: EcSpacing.md),
                child: Text(
                  'This patient is a minor: the decision is recorded as given by the verified guardian.',
                  style: EcTypography.helper,
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      EcPrimaryButton(
        label: 'Record',
        compact: true,
        onPressed: _decision == null
            ? null
            : () => Navigator.of(context).pop({
                'type': _purpose['type'],
                'decision': _decision,
                'method': _method,
                'by': widget.guardianVerified
                    ? {'type': 'guardian'}
                    : {'type': 'patient'},
                if (_purpose['type'] == 'other') 'purpose': _custom.text.trim(),
              }),
      ),
    ],
  );
}

// -------------------------------------------------------------- documents

class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ListQuery('/patients/$patientId/documents');
    final state = ref.watch(pagedListProvider(query));
    final repo = ref.read(controlPlaneRepositoryProvider);
    final canManage = can(ref, ClinicPermission.patientDocumentsManage);
    void reload() => ref.invalidate(pagedListProvider(query));

    Future<void> upload() async {
      final file = await ref.read(documentPickerProvider)();
      if (file == null || !context.mounted) return;
      final meta = await showRecordDialog(
        context,
        title: 'Upload ${file.name}',
        confirmLabel: 'Upload',
        note:
            'Needs the patient\'s document consent. Files are stored privately for this clinic only.',
        fields: [
          const FieldSpec(
            'name',
            'Document name',
            required: true,
            maxLength: 120,
          ),
          const FieldSpec(
            'category',
            'Category',
            kind: FieldKind.choice,
            required: true,
            options: [
              'previous_report',
              'lab_report',
              'scanned_record',
              'referral',
              'patient_prescription',
              'other',
            ],
          ),
          const FieldSpec('description', 'Description', maxLength: 300),
          const FieldSpec(
            'source',
            'Source',
            kind: FieldKind.choice,
            options: [
              'patient_provided',
              'external_clinic',
              'clinic_scanned',
              'other',
            ],
          ),
          if (can(ref, ClinicPermission.historyView))
            const FieldSpec(
              'classification',
              'Access',
              kind: FieldKind.choice,
              options: ['normal', 'restricted'],
            ),
        ],
        initial: {'name': file.name},
      );
      if (meta == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.sendMap('POST', '/patients/$patientId/documents', {
          ...meta,
          'contentType': file.contentType,
          'dataBase64': base64Encode(file.bytes),
        }),
        success: 'Document uploaded.',
        after: reload,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        _Toolbar(
          text:
              'Reports and records for this clinic. Access is checked and logged every time.',
          action: canManage
              ? EcPrimaryButton(
                  label: 'Upload document',
                  icon: Icons.upload_file,
                  compact: true,
                  onPressed: upload,
                )
              : null,
        ),
        const SizedBox(height: EcSpacing.md),
        if (state.loading)
          const EcLoadingIndicator()
        else if (state.error != null)
          EcErrorState(
            title: 'Could not load documents',
            message: state.error!.displayMessage,
            onRetry: reload,
          )
        else if (state.items.isEmpty)
          const EcEmptyState(
            title: 'No documents',
            message: 'Upload an external report or scanned record.',
          )
        else
          for (final d in state.items)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.sm),
              child: EcCard(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('${d['name']}'),
                    content: SizedBox(
                      width: 420,
                      child: KeyValues([
                        ('Category', Fmt.humanize(d['category'])),
                        ('Type', d['contentType']),
                        ('Size', '${((d['size'] as int?) ?? 0) ~/ 1024} KB'),
                        ('Source', Fmt.humanize(d['source'])),
                        ('Verification', Fmt.humanize(d['verificationStatus'])),
                        ('Access', Fmt.humanize(d['classification'])),
                        ('Uploaded', Fmt.dateTime(d['uploadedAt'])),
                        ('Description', d['description']),
                      ]),
                    ),
                    actions: [
                      if (canManage)
                        TextButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            final reason = await askReason(
                              context,
                              title: 'Remove document?',
                              message:
                                  'It is hidden from the list. The stored file is retained under the clinic\'s retention policy.',
                              confirmLabel: 'Remove',
                            );
                            if (reason == null || !context.mounted) return;
                            await runAction(
                              context,
                              action: () => repo.deleteAt(
                                '/patients/$patientId/documents/${d['documentId']}?reason=${Uri.encodeQueryComponent(reason)}',
                              ),
                              success: 'Document removed.',
                              after: reload,
                            );
                          },
                          child: const Text('Remove'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: EcSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d['name']}', style: EcTypography.bodyStrong),
                          Text(
                            '${Fmt.humanize(d['category'])} · ${Fmt.date(d['uploadedAt'])}',
                            style: EcTypography.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                    if (d['classification'] == 'restricted')
                      const EcStatusChip(
                        label: 'Restricted',
                        tone: EcStatusTone.warning,
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// --------------------------------------------------------------- identity

class IdentityTab extends ConsumerWidget {
  const IdentityTab({
    required this.patient,
    required this.onChanged,
    super.key,
  });

  final Json patient;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${patient['patientId']}';
    final linked = patient['patientAccountId'] != null;
    final repo = ref.read(controlPlaneRepositoryProvider);
    final open = patient['status'] == 'active';
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        Section(
          title: 'Patient account link',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EcStatusChip(
                    label: linked
                        ? 'Linked to a patient account'
                        : 'Not linked',
                    tone: linked ? EcStatusTone.success : EcStatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: EcSpacing.md),
              const Text(
                'Linking lets the patient see their own information at this clinic in the app. It never shares this record with another clinic, and a matching phone number or e-mail never links anything.',
              ),
              const SizedBox(height: EcSpacing.md),
              if (!linked && open)
                EcPrimaryButton(
                  label: 'Issue link code',
                  compact: true,
                  onPressed: () async {
                    final r = await showRecordDialog(
                      context,
                      title: 'Issue link code',
                      confirmLabel: 'Issue code',
                      note:
                          'Check the patient\'s identity in person first. The patient enters the code in their app with a verified e-mail. It works once and expires in 24 hours.',
                      fields: const [
                        FieldSpec(
                          'verificationMethod',
                          'How did you identify them?',
                          kind: FieldKind.choice,
                          required: true,
                          options: [
                            'government_id_sighted',
                            'other_document_sighted',
                            'known_patient_in_person',
                          ],
                        ),
                      ],
                    );
                    if (r == null || !context.mounted) return;
                    final ok = await showEcConfirmDialog(
                      context,
                      title: 'Confirm identity check',
                      message:
                          'I have identified this patient in person and they asked to link their account.',
                      confirmLabel: 'Confirm and issue',
                    );
                    if (!ok || !context.mounted) return;
                    try {
                      final res = await repo.sendMap(
                        'POST',
                        '/patients/$id/link-account',
                        {...r, 'identityConfirmed': true},
                      );
                      if (context.mounted) {
                        await _showCode(context, res);
                      }
                    } on ApiFailure catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(failureText(e)),
                            backgroundColor: EcColors.error,
                          ),
                        );
                      }
                    }
                  },
                ),
              if (linked)
                EcSecondaryButton(
                  label: 'Unlink account',
                  compact: true,
                  onPressed: () async {
                    final reason = await askReason(
                      context,
                      title: 'Unlink patient account?',
                      message:
                          'The clinic keeps this record. The patient can be linked again later.',
                      confirmLabel: 'Unlink',
                    );
                    if (reason == null || !context.mounted) return;
                    await runAction(
                      context,
                      action: () => repo.sendMap(
                        'POST',
                        '/patients/$id/unlink-account',
                        {'reason': reason},
                      ),
                      success: 'Account unlinked.',
                      after: onChanged,
                    );
                  },
                ),
            ],
          ),
        ),
        const Section(
          title: 'Family and dependents',
          child: Text(
            'Family relationships belong to the patient\'s own account and are managed by the patient in the app. Clinics see no relationship details, and a relationship never gives access to this record.',
          ),
        ),
      ],
    );
  }

  Future<void> _showCode(BuildContext context, Json res) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Link code'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EcInlineMessage(
              tone: EcStatusTone.warning,
              message:
                  'Shown only once. Give it to the patient in person; do not send it by message.',
            ),
            const SizedBox(height: EcSpacing.lg),
            SelectableText(
              '${res['code']}',
              key: const Key('link-code'),
              style: EcTypography.subsectionTitle,
            ),
            const SizedBox(height: EcSpacing.sm),
            Text(
              'Expires ${Fmt.dateTime(res['expiresAt'])}',
              style: EcTypography.helper,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: '${res['code']}')),
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ audit

class AuditTab extends ConsumerWidget {
  const AuditTab({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ListQuery('/patients/$patientId/audit-logs');
    final state = ref.watch(pagedListProvider(query));
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        Text(
          'Who did what, and when. Entries hold references only, never clinical content.',
          style: EcTypography.bodySecondary,
        ),
        const SizedBox(height: EcSpacing.md),
        if (state.loading)
          const EcLoadingIndicator()
        else if (state.error != null)
          EcErrorState(
            title: 'Could not load the audit history',
            message: state.error!.displayMessage,
            onRetry: () => ref.invalidate(pagedListProvider(query)),
          )
        else if (state.items.isEmpty)
          const EcEmptyState(
            title: 'No entries',
            message: 'Nothing recorded yet.',
          )
        else
          for (final e in state.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(Fmt.humanize('${e['action']}'.replaceAll('.', ' '))),
              subtitle: Text(
                '${Fmt.dateTime(e['timestamp'])} · ${Fmt.humanize(e['actorRole'])}${e['reason'] == null ? '' : ' · ${e['reason']}'}',
              ),
            ),
        if (state.hasMore)
          Center(
            child: EcSecondaryButton(
              label: 'Load more',
              compact: true,
              onPressed: () =>
                  ref.read(pagedListProvider(query).notifier).loadMore(),
            ),
          ),
      ],
    );
  }
}

/// Explanatory text with an optional primary action. A [Wrap] keeps the
/// full-height button from receiving unbounded width.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: EcSpacing.md,
    runSpacing: EcSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(text, style: EcTypography.bodySecondary),
      ),
      ?action,
    ],
  );
}
