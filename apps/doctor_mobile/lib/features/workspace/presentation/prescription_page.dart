import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Prescription editor (draft), authorized preview (finalized) and amendment.
/// Only what the doctor types appears here; nothing is suggested or checked
/// for clinical suitability.
class PrescriptionPage extends ConsumerStatefulWidget {
  const PrescriptionPage({required this.prescriptionId, super.key});

  final String prescriptionId;

  @override
  ConsumerState<PrescriptionPage> createState() => _PrescriptionState();
}

class _PrescriptionState extends ConsumerState<PrescriptionPage> {
  bool _busy = false;

  static const _medFields = [
    FieldSpec('name', 'Medicine', required: true, maxLength: 120),
    FieldSpec('strength', 'Strength', maxLength: 40),
    FieldSpec('dosage', 'Dose (e.g. 1 tablet)', required: true, maxLength: 60),
    FieldSpec('route', 'Route', maxLength: 30),
    FieldSpec(
      'frequency',
      'Frequency (e.g. twice daily)',
      required: true,
      maxLength: 60,
    ),
    FieldSpec(
      'durationValue',
      'Duration (number)',
      required: true,
      maxLength: 3,
    ),
    FieldSpec(
      'durationUnit',
      'Duration unit',
      kind: FieldKind.choice,
      options: ['days', 'weeks', 'months'],
      required: true,
    ),
    FieldSpec(
      'foodRelation',
      'With food',
      kind: FieldKind.choice,
      options: ['before_food', 'after_food', 'with_food', 'any'],
    ),
    FieldSpec(
      'instructions',
      'Instructions',
      kind: FieldKind.multiline,
      maxLength: 300,
    ),
  ];

  List<Json> _meds(Json rx) => ((rx['medicines'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, Object?>())
      .toList();

  Json _typed(Json v) => {
    ...v,
    if (v['durationValue'] != null)
      'durationValue':
          int.tryParse('${v['durationValue']}') ?? v['durationValue'],
  };

  Future<void> _saveMeds(Json rx, List<Json> meds) async {
    setState(() => _busy = true);
    await runAction(
      context,
      action: () => ref.read(clinicalRepositoryProvider).send(
        'PATCH',
        '/prescriptions/${widget.prescriptionId}',
        {'medicines': meds, 'expectedRev': rx['rev']},
      ),
      success: 'Prescription saved.',
      after: () => refreshAll(ref),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finalize(Json rx) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Authorize prescription?'),
        content: const Text(
          'You confirm this prescription as the responsible doctor. It cannot '
          'be edited afterwards; changes need a recorded amendment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Authorize'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    await runAction(
      context,
      action: () => ref.read(clinicalRepositoryProvider).send(
        'POST',
        '/prescriptions/${widget.prescriptionId}/finalize',
        null,
        {'Idempotency-Key': newIdempotencyKey()},
      ),
      success: 'Prescription authorized.',
      after: () => refreshAll(ref),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _amend(Json rx) async {
    final reason = await askReason(
      context,
      title: 'Amend prescription',
      message:
          'A new draft is created from this prescription. The original stays on record.',
      confirmLabel: 'Create amendment',
    );
    if (reason == null || !mounted) return;
    try {
      final r = await ref.read(clinicalRepositoryProvider).send(
        'POST',
        '/prescriptions/${widget.prescriptionId}/amend',
        {'reason': reason},
      );
      refreshAll(ref);
      if (mounted) context.go('/prescriptions/${r['prescriptionId']}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = prescriptionQuery(widget.prescriptionId);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (rx) {
        final status = '${rx['status']}';
        final draft = status == 'draft';
        final meds = _meds(rx);
        final versions = ((rx['versions'] as List?) ?? const []).cast<Json>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: rx['number'] != null
                  ? 'Prescription ${rx['number']}'
                  : 'Prescription (draft)',
              subtitle: '${rx['patientName'] ?? ''} · version ${rx['version']}',
              actions: [
                statusChip(status),
                sized(
                  EcSecondaryButton(
                    label: 'Back to consultation',
                    icon: Icons.arrow_back,
                    onPressed: () =>
                        context.go('/consultations/${rx['consultationId']}'),
                  ),
                  300,
                ),
              ],
            ),
            if (rx['amendReason'] != null)
              EcInlineMessage(
                tone: EcStatusTone.info,
                message: 'Amendment reason: ${rx['amendReason']}',
              ),
            Section(
              title: '${rx['clinicName'] ?? 'Clinic'}',
              trailing: draft
                  ? sized(
                      EcSecondaryButton(
                        label: 'Add medicine',
                        icon: Icons.add,
                        onPressed: _busy
                            ? null
                            : () async {
                                final v = await showFormDialog(
                                  context,
                                  title: 'Add medicine',
                                  fields: _medFields,
                                );
                                if (v == null) return;
                                await _saveMeds(rx, [...meds, _typed(v)]);
                              },
                      ),
                      300,
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meds.isEmpty) const Text('No medicines added.'),
                  for (var i = 0; i < meds.length; i++)
                    ListTile(
                      key: Key('med-$i'),
                      dense: true,
                      title: Text(
                        '${meds[i]['name']} ${meds[i]['strength'] ?? ''}'
                            .trim(),
                      ),
                      subtitle: Text(
                        '${meds[i]['dosage']} · ${meds[i]['frequency']} · '
                        '${meds[i]['durationValue']} ${meds[i]['durationUnit']}'
                        '${meds[i]['foodRelation'] != null ? ' · ${humanize(meds[i]['foodRelation'])}' : ''}'
                        '${meds[i]['instructions'] != null ? '\n${meds[i]['instructions']}' : ''}',
                      ),
                      trailing: draft
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final v = await showFormDialog(
                                      context,
                                      title: 'Edit medicine',
                                      fields: _medFields,
                                      initial: meds[i],
                                    );
                                    if (v == null) return;
                                    final next = [...meds]
                                      ..[i] = _typed({...meds[i], ...v});
                                    await _saveMeds(rx, next);
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _saveMeds(rx, [...meds]..removeAt(i)),
                                ),
                              ],
                            )
                          : null,
                    ),
                  if (rx['notes'] != null) ...[
                    const SizedBox(height: EcSpacing.md),
                    Text('${rx['notes']}'),
                  ],
                  const SizedBox(height: EcSpacing.md),
                  Text(
                    '${rx['disclaimer'] ?? ''}',
                    style: EcTypography.bodySecondary,
                  ),
                ],
              ),
            ),
            if (draft)
              sized(
                EcPrimaryButton(
                  label: 'Authorize prescription',
                  onPressed: _busy || meds.isEmpty ? null : () => _finalize(rx),
                ),
                300,
              )
            else if (status == 'finalized')
              sized(
                EcSecondaryButton(
                  label: 'Amend',
                  icon: Icons.edit_note,
                  onPressed: () => _amend(rx),
                ),
              ),
            if (versions.length > 1)
              Section(
                title: 'Versions',
                child: Column(
                  children: [
                    for (final v in versions)
                      ListTile(
                        dense: true,
                        title: Text('Version ${v['version']}'),
                        subtitle: Text(shortDateTime(v['finalizedAt'])),
                        trailing: statusChip(v['status']),
                        onTap: () =>
                            context.go('/prescriptions/${v['prescriptionId']}'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
