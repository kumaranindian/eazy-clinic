import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// The consultation workspace: complaint, findings, diagnosis, plan,
/// prescriptions, investigation requests and follow-up. Finalized
/// consultations are read-only; changes go through a recorded amendment.
class ConsultationPage extends ConsumerStatefulWidget {
  const ConsultationPage({required this.consultationId, super.key});

  final String consultationId;

  @override
  ConsumerState<ConsultationPage> createState() => _ConsultationState();
}

class _ConsultationState extends ConsumerState<ConsultationPage> {
  static const _fields = <String, (String, String, int)>{
    'reason': ('chiefComplaint', 'Chief complaint', 1),
    'symptoms': ('chiefComplaint', 'Symptoms (comma separated)', 1),
    'ccNotes': ('chiefComplaint', 'Complaint notes', 3),
    'examination': ('observations', 'Examination findings', 4),
    'obsNotes': ('observations', 'Observation notes', 3),
    'assessment': ('assessment', 'Assessment notes', 3),
    'recommendations': ('treatmentPlan', 'Treatment plan', 4),
    'patientInstructions': ('treatmentPlan', 'Instructions for the patient', 3),
  };
  static const _keyIn = {
    'ccNotes': 'notes',
    'obsNotes': 'notes',
    'assessment': 'notes',
  };

  final Map<String, TextEditingController> _c = {
    for (final k in _fields.keys) k: TextEditingController(),
  };
  String? _loadedKey;
  bool _dirty = false;
  bool _amending = false;
  bool _busy = false;
  final List<Json> _dxChanges = [];

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _key(Json c) => '${c['version']}-${c['revision']}-${c['status']}';

  Map<dynamic, dynamic> _section(Json c, String name) =>
      (c[name] as Map?) ?? const {};

  void _load(Json c) {
    if (_loadedKey == _key(c)) return;
    _loadedKey = _key(c);
    _dirty = false;
    final cc = _section(c, 'chiefComplaint');
    final symptoms = ((cc['symptoms'] as List?) ?? const [])
        .map((s) => (s as Map)['name'])
        .join(', ');
    final values = <String, Object?>{
      'reason': cc['reason'],
      'symptoms': symptoms,
      'ccNotes': cc['notes'],
      'examination': _section(c, 'observations')['examination'],
      'obsNotes': _section(c, 'observations')['notes'],
      'assessment': _section(c, 'assessment')['notes'],
      'recommendations': _section(c, 'treatmentPlan')['recommendations'],
      'patientInstructions': _section(
        c,
        'treatmentPlan',
      )['patientInstructions'],
    };
    for (final e in values.entries) {
      _c[e.key]!.text = '${e.value ?? ''}';
    }
  }

  Map<String, Object?> _sections(Json c) {
    final out = <String, Map<String, Object?>>{};
    for (final e in _fields.entries) {
      final (section, _, _) = e.value;
      final text = _c[e.key]!.text.trim();
      final inner = out.putIfAbsent(section, () => {});
      if (e.key == 'symptoms') {
        final old = {
          for (final s
              in ((_section(c, 'chiefComplaint')['symptoms'] as List?) ??
                  const []))
            '${(s as Map)['name']}': s.cast<String, Object?>(),
        };
        inner['symptoms'] = [
          for (final n
              in text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.length >= 2))
            old[n] ?? {'name': n},
        ];
      } else if (text.isNotEmpty) {
        inner[_keyIn[e.key] ?? e.key] = text;
      }
    }
    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  Future<bool> _save(Json c) async {
    final ok = await runAction(
      context,
      action: () => ref.read(clinicalRepositoryProvider).send(
        'PATCH',
        '/consultations/${widget.consultationId}',
        {..._sections(c), 'expectedVersion': c['version']},
      ),
      success: 'Consultation saved.',
    );
    if (ok) {
      _dirty = false;
      refreshAll(ref);
    }
    return ok;
  }

  Future<void> _post(String path, String ok, [Json? body]) async {
    setState(() => _busy = true);
    await runAction(
      context,
      action: () =>
          ref.read(clinicalRepositoryProvider).send('POST', path, body),
      success: ok,
      after: () => refreshAll(ref),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finalize(Json c) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalize consultation?'),
        content: const Text(
          'A finalized consultation is read-only. Later changes need a '
          'recorded amendment with a reason.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (_dirty && !await _save(c)) return;
    if (!mounted) return;
    await _post(
      '/consultations/${widget.consultationId}/finalize',
      'Consultation finalized.',
    );
  }

  Future<void> _submitAmendment(Json c) async {
    final reason = await askReason(
      context,
      title: 'Amend consultation',
      message:
          'The original record is preserved. Your reason, name and time are recorded.',
      confirmLabel: 'Record amendment',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      action: () => ref
          .read(clinicalRepositoryProvider)
          .send('POST', '/consultations/${widget.consultationId}/amend', {
            ..._sections(c),
            'reason': reason,
            if (_dxChanges.isNotEmpty) 'diagnosisChanges': _dxChanges,
          }),
      success: 'Amendment recorded.',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _amending = false;
        _dxChanges.clear();
      }
    });
    if (ok) refreshAll(ref);
  }

  Future<Json?> _dxDialog({Json? initial}) => showFormDialog(
    context,
    title: initial == null ? 'Add diagnosis' : 'Edit diagnosis',
    note: 'Enter the diagnosis you have made. Nothing is suggested.',
    initial: initial ?? const {'kind': 'primary', 'certainty': 'provisional'},
    fields: const [
      FieldSpec('label', 'Diagnosis', required: true),
      FieldSpec(
        'kind',
        'Kind',
        kind: FieldKind.choice,
        options: ['primary', 'secondary', 'differential'],
        required: true,
      ),
      FieldSpec(
        'certainty',
        'Certainty',
        kind: FieldKind.choice,
        options: ['provisional', 'confirmed'],
        required: true,
      ),
      FieldSpec('code', 'Code (optional)', maxLength: 20),
      FieldSpec('codeSystem', 'Code system (with code)', maxLength: 30),
      FieldSpec('notes', 'Notes', kind: FieldKind.multiline, maxLength: 1000),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final q = consultationQuery(widget.consultationId);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (c) {
        _load(c);
        final status = '${c['status']}';
        final open = status == 'draft' || status == 'in_progress';
        final editable = open || _amending;
        final dx = ((c['diagnoses'] as List?) ?? const []).cast<Json>();
        final rx = ((c['prescriptions'] as List?) ?? const []).cast<Json>();
        final inv = ((c['investigations'] as List?) ?? const []).cast<Json>();
        final fu = ((c['followups'] as List?) ?? const []).cast<Json>();
        Widget field(String k) => Padding(
          padding: const EdgeInsets.only(bottom: EcSpacing.md),
          child: EcTextField(
            label: _fields[k]!.$2,
            controller: _c[k],
            maxLines: _fields[k]!.$3,
            enabled: editable,
            onChanged: (_) => _dirty = true,
          ),
        );
        return PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard unsaved changes?'),
                content: const Text('Your latest edits have not been saved.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep editing'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            );
            if (leave == true && context.mounted) {
              setState(() => _dirty = false);
              context.go('/patients/${c['patientId']}');
            }
          },
          child: ListView(
            padding: const EdgeInsets.all(EcSpacing.lg),
            children: [
              PageHeader(
                title: '${c['patientName']}',
                subtitle:
                    '${c['patientMrn'] ?? ''} · ${humanize(c['type'])} · ${shortDateTime(c['consultationAt'])}',
                actions: [
                  statusChip(status),
                  if (open && status == 'draft')
                    sized(
                      EcSecondaryButton(
                        label: 'Start consultation',
                        onPressed: _busy
                            ? null
                            : () => _post(
                                '/consultations/${widget.consultationId}/start',
                                'Consultation started.',
                              ),
                      ),
                    ),
                ],
              ),
              if (status == 'amended' || status == 'finalized')
                EcInlineMessage(
                  tone: EcStatusTone.info,
                  message: status == 'amended'
                      ? 'Finalized and amended ${c['amendmentCount']} time(s). The original is preserved.'
                      : 'Finalized and read-only.',
                ),
              Section(
                title: 'Chief complaint',
                child: Column(
                  children: [
                    field('reason'),
                    field('symptoms'),
                    field('ccNotes'),
                  ],
                ),
              ),
              Section(
                title: 'Examination and observations',
                child: Column(
                  children: [field('examination'), field('obsNotes')],
                ),
              ),
              Section(
                title: 'Diagnosis',
                trailing: editable
                    ? sized(
                        EcSecondaryButton(
                          label: 'Add diagnosis',
                          icon: Icons.add,
                          onPressed: () async {
                            final v = await _dxDialog();
                            if (v == null || !context.mounted) return;
                            if (_amending) {
                              setState(
                                () => _dxChanges.add({'op': 'add', ...v}),
                              );
                            } else {
                              await runAction(
                                context,
                                action: () => ref
                                    .read(clinicalRepositoryProvider)
                                    .send(
                                      'POST',
                                      '/consultations/${widget.consultationId}/diagnoses',
                                      v,
                                    ),
                                success: 'Diagnosis added.',
                                after: () => refreshAll(ref),
                              );
                            }
                          },
                        ),
                        300,
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dx.isEmpty) const Text('No diagnosis recorded yet.'),
                    for (final d in dx)
                      ListTile(
                        key: Key('dx-${d['diagnosisId']}'),
                        dense: true,
                        title: Text(
                          '${d['label']}${d['code'] != null ? ' (${d['code']})' : ''}',
                        ),
                        subtitle: Text(
                          '${humanize(d['kind'])} · ${humanize(d['certainty'])}',
                        ),
                        trailing: _amending
                            ? IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => setState(
                                  () => _dxChanges.add({
                                    'op': 'remove',
                                    'diagnosisId': d['diagnosisId'],
                                  }),
                                ),
                              )
                            : open
                            ? IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final v = await _dxDialog(initial: d);
                                  if (v == null || !context.mounted) return;
                                  await runAction(
                                    context,
                                    action: () => ref
                                        .read(clinicalRepositoryProvider)
                                        .send(
                                          'PATCH',
                                          '/consultations/${widget.consultationId}/diagnoses/${d['diagnosisId']}',
                                          v,
                                        ),
                                    success: 'Diagnosis updated.',
                                    after: () => refreshAll(ref),
                                  );
                                },
                              )
                            : null,
                      ),
                    for (final ch in _dxChanges)
                      Text(
                        'Pending amendment: ${ch['op']} ${ch['label'] ?? ch['diagnosisId']}',
                        style: EcTypography.bodySecondary,
                      ),
                  ],
                ),
              ),
              Section(
                title: 'Assessment and treatment plan',
                child: Column(
                  children: [
                    field('assessment'),
                    field('recommendations'),
                    field('patientInstructions'),
                  ],
                ),
              ),
              Section(
                title: 'Prescriptions',
                trailing: open
                    ? sized(
                        EcSecondaryButton(
                          label: 'New prescription',
                          icon: Icons.medication_outlined,
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    final r = await ref
                                        .read(clinicalRepositoryProvider)
                                        .send(
                                          'POST',
                                          '/consultations/${widget.consultationId}/prescriptions',
                                          {},
                                        );
                                    if (context.mounted) {
                                      context.go(
                                        '/prescriptions/${r['prescriptionId']}',
                                      );
                                    }
                                  } on ApiFailure catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(failureText(e))),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                        ),
                        300,
                      )
                    : null,
                child: Column(
                  children: [
                    if (rx.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No prescriptions.'),
                      ),
                    for (final p in rx)
                      ListTile(
                        key: Key('rx-${p['prescriptionId']}'),
                        dense: true,
                        title: Text(
                          '${p['number'] ?? 'Draft'} · ${p['medicineCount']} medicine(s)',
                        ),
                        subtitle: Text('Version ${p['version']}'),
                        trailing: statusChip(p['status']),
                        onTap: () =>
                            context.go('/prescriptions/${p['prescriptionId']}'),
                      ),
                  ],
                ),
              ),
              Section(
                title: 'Investigation requests',
                trailing: open
                    ? sized(
                        EcSecondaryButton(
                          label: 'Request investigation',
                          icon: Icons.biotech_outlined,
                          onPressed: () async {
                            final v = await showFormDialog(
                              context,
                              title: 'Request investigation',
                              note:
                                  'Recorded as a request only. Laboratory processing is not available yet.',
                              fields: const [
                                FieldSpec('testName', 'Test', required: true),
                                FieldSpec(
                                  'indication',
                                  'Indication',
                                  required: true,
                                  maxLength: 300,
                                ),
                                FieldSpec(
                                  'priority',
                                  'Priority',
                                  kind: FieldKind.choice,
                                  options: ['routine', 'urgent', 'stat'],
                                ),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await runAction(
                              context,
                              action: () => ref
                                  .read(clinicalRepositoryProvider)
                                  .send(
                                    'POST',
                                    '/consultations/${widget.consultationId}/investigations',
                                    v,
                                  ),
                              success: 'Investigation requested.',
                              after: () => refreshAll(ref),
                            );
                          },
                        ),
                        300,
                      )
                    : null,
                child: Column(
                  children: [
                    if (inv.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('None requested.'),
                      ),
                    for (final i in inv)
                      ListTile(
                        dense: true,
                        title: Text('${i['testName']}'),
                        subtitle: Text(
                          '${humanize(i['priority'])} · results not available yet',
                        ),
                      ),
                  ],
                ),
              ),
              Section(
                title: 'Follow-up',
                trailing: status != 'draft' || open
                    ? sized(
                        EcSecondaryButton(
                          label: 'Schedule follow-up',
                          icon: Icons.event_repeat,
                          onPressed: () async {
                            final v = await showFormDialog(
                              context,
                              title: 'Schedule follow-up',
                              fields: const [
                                FieldSpec(
                                  'recommendedDate',
                                  'Date',
                                  kind: FieldKind.date,
                                  required: true,
                                ),
                                FieldSpec(
                                  'reason',
                                  'Reason',
                                  required: true,
                                  maxLength: 300,
                                ),
                                FieldSpec(
                                  'instructions',
                                  'Instructions',
                                  kind: FieldKind.multiline,
                                  maxLength: 1000,
                                ),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await runAction(
                              context,
                              action: () => ref
                                  .read(clinicalRepositoryProvider)
                                  .send(
                                    'POST',
                                    '/consultations/${widget.consultationId}/followups',
                                    v,
                                  ),
                              success: 'Follow-up scheduled.',
                              after: () => refreshAll(ref),
                            );
                          },
                        ),
                        300,
                      )
                    : null,
                child: Column(
                  children: [
                    if (fu.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No follow-up.'),
                      ),
                    for (final f in fu)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${shortDate(f['recommendedDate'])} · ${f['reason'] ?? ''}',
                        ),
                        trailing: statusChip(f['status']),
                      ),
                  ],
                ),
              ),
              if (open || _amending)
                Wrap(
                  spacing: EcSpacing.md,
                  runSpacing: EcSpacing.md,
                  children: [
                    if (open) ...[
                      sized(
                        EcSecondaryButton(
                          label: 'Save draft',
                          onPressed: _busy ? null : () => _save(c),
                        ),
                      ),
                      sized(
                        EcPrimaryButton(
                          label: 'Finalize',
                          onPressed: _busy ? null : () => _finalize(c),
                        ),
                      ),
                    ] else ...[
                      sized(
                        EcSecondaryButton(
                          label: 'Cancel amendment',
                          onPressed: () => setState(() {
                            _amending = false;
                            _loadedKey = null;
                            _dxChanges.clear();
                          }),
                        ),
                      ),
                      sized(
                        EcPrimaryButton(
                          label: 'Record amendment',
                          onPressed: _busy ? null : () => _submitAmendment(c),
                        ),
                      ),
                    ],
                  ],
                )
              else
                sized(
                  EcSecondaryButton(
                    label: 'Amend',
                    icon: Icons.edit_note,
                    onPressed: () => setState(() => _amending = true),
                  ),
                ),
              const SizedBox(height: EcSpacing.lg),
              if (status == 'amended')
                _Amendments(consultationId: widget.consultationId),
            ],
          ),
        );
      },
    );
  }
}

class _Amendments extends ConsumerWidget {
  const _Amendments({required this.consultationId});

  final String consultationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/consultations/$consultationId/amendments');
    return Section(
      title: 'Amendment history',
      child: AsyncBody(
        value: ref.watch(mapProvider(q)),
        onRetry: () => ref.invalidate(mapProvider(q)),
        builder: (m) => Column(
          children: [
            for (final a
                in ((m['amendments'] as List?) ?? const []).cast<Json>())
              ListTile(
                dense: true,
                title: Text(
                  'Revision ${a['revision']} · ${shortDateTime(a['amendedAt'] ?? a['createdAt'])}',
                ),
                subtitle: Text('${a['reason']}'),
              ),
          ],
        ),
      ),
    );
  }
}
