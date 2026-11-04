import 'dart:convert';
import 'dart:typed_data';

import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../finance/finance_kit.dart';
import '../patients/dialogs.dart';
import '../scheduling/scheduling_providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

/// Statuses of a laboratory order, in lifecycle order.
const labOrderStatuses = [
  'requested',
  'accepted',
  'sample_pending',
  'recollection_required',
  'sample_collected',
  'processing',
  'result_entered',
  'verification_pending',
  'verified',
  'published',
  'rejected',
  'cancelled',
];

const _priorities = ['routine', 'urgent', 'emergency'];

/// Picks the external report file (replaceable in tests).
final externalReportPickerProvider =
    Provider<Future<({String name, Uint8List bytes})?> Function()>(
      (ref) => () async {
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Reports',
              extensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
            ),
          ],
        );
        if (file == null) return null;
        return (name: file.name, bytes: await file.readAsBytes());
      },
    );

/// Saves a downloaded report (replaceable in tests).
final reportSaverProvider =
    Provider<Future<void> Function(String name, Uint8List bytes)>(
      (ref) => (name, bytes) async {
        await XFile.fromData(
          bytes,
          name: name,
          mimeType: 'application/pdf',
        ).saveTo(name);
      },
    );

String flagLabel(Object? f) => switch ('$f') {
  'low' => 'Low',
  'high' => 'High',
  'abnormal' => 'Abnormal',
  'critical_low' => 'Critical low',
  'critical_high' => 'Critical high',
  'critical' => 'Critical',
  'unit_mismatch' => 'Unit differs from range',
  'not_assessed' => 'No reference range',
  'normal' => 'Normal',
  _ => '',
};

Color flagColor(Object? f) {
  final s = '$f';
  if (s.startsWith('critical')) return EcColors.error;
  if (s == 'low' || s == 'high' || s == 'abnormal') return EcColors.warning;
  return EcColors.textSecondary;
}

// ---------------------------------------------------------------- dashboard

class LabDashboardPage extends ConsumerWidget {
  const LabDashboardPage({super.key});

  static const _tiles = [
    ('ordersInPeriod', 'Orders today'),
    ('pendingOrders', 'Open orders'),
    ('samplesAwaitingCollection', 'Samples to collect'),
    ('processing', 'In processing'),
    ('awaitingVerification', 'Awaiting verification'),
    ('publishedInPeriod', 'Reports published'),
    ('recollections', 'Recollections needed'),
    ('rejectedSamplesInPeriod', 'Samples rejected'),
    ('urgentOpen', 'Urgent or emergency open'),
    ('overdue', 'Overdue'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    final q = Query('/laboratory/dashboard', {'branchId': branch ?? ''});
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final defs = ((d['definitions'] as Map?) ?? const {})
            .cast<String, Object?>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Laboratory',
              subtitle: 'Live counts from laboratory orders and samples.',
            ),
            if (d['truncated'] == true)
              const EcInlineMessage(
                tone: EcStatusTone.warning,
                message:
                    'Very many orders match; figures cover the most recent ones only.',
              ),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                for (final (k, label) in _tiles)
                  SizedBox(
                    width: 220,
                    child: EcCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d[k] ?? 0}',
                            key: Key('lab-tile-$k'),
                            style: EcTypography.sectionTitle,
                          ),
                          const SizedBox(height: 2),
                          Text(label, style: EcTypography.bodySecondary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: EcSpacing.lg),
            Section(
              title: 'Definitions',
              child: KeyValues([
                for (final e in defs.entries) (Fmt.humanize(e.key), e.value),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------- orders

class LabOrdersPage extends ConsumerWidget {
  const LabOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    final canCreate = can(ref, ClinicPermission.labOrdersManage);
    return ListScreen(
      title: 'Laboratory orders',
      subtitle: 'Requests from doctors and the laboratory desk.',
      path: '/laboratory/orders',
      statusOptions: labOrderStatuses,
      searchHint: 'Order number (exact)',
      extraParams: {'branchId': ?branch},
      extraDropdown: ('Priority', 'priority', _priorities),
      emptyTitle: 'No laboratory orders',
      emptyMessage:
          'Orders appear here when a doctor or the desk requests tests.',
      actions: [
        if (canCreate)
          sized(
            EcPrimaryButton(
              key: const Key('new-lab-order'),
              label: 'New order',
              onPressed: () => _newOrder(context, ref),
            ),
          ),
      ],
      rowBuilder: (context, r) => RowCard(
        title: '${r['orderNumber']} · ${r['patientName'] ?? ''}',
        subtitle:
            '${((r['tests'] as List?) ?? const []).join(', ')} · ${Fmt.dateTime(r['createdAt'])}'
            '${r['priority'] == 'routine' ? '' : ' · ${Fmt.humanize(r['priority'])}'}',
        status: r['status'],
        onTap: () => context.go('/clinic/laboratory/orders/${r['orderId']}'),
      ),
    );
  }

  Future<void> _newOrder(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(controlPlaneRepositoryProvider);
    final patient = await pickPatient(context);
    if (patient == null || !context.mounted) return;
    final tests = await repo.getList('/laboratory/tests', {
      'status': 'active',
      'limit': '100',
    });
    if (!context.mounted) return;
    if (tests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add tests to the catalogue first.')),
      );
      return;
    }
    final v = await showRecordDialog(
      context,
      title: 'New order for ${patient['fullName']}',
      confirmLabel: 'Create order',
      fields: [
        FieldSpec(
          'test',
          'Test',
          kind: FieldKind.choice,
          required: true,
          options: [for (final t in tests) '${t['code']} · ${t['name']}'],
        ),
        const FieldSpec(
          'priority',
          'Priority',
          kind: FieldKind.choice,
          options: _priorities,
        ),
      ],
    );
    if (v == null || !context.mounted) return;
    final code = '${v['test']}'.split(' · ').first;
    final test = tests.firstWhere((t) => t['code'] == code);
    final branch =
        ref.read(activeBranchProvider) ?? '${patient['branchId'] ?? ''}';
    await runAction(
      context,
      action: () async {
        final o = await repo.sendMap(
          'POST',
          '/laboratory/orders',
          {
            'patientId': patient['patientId'],
            'branchId': branch,
            'priority': v['priority'] ?? 'routine',
            'tests': [
              {'testId': test['testId']},
            ],
          },
          {
            'Idempotency-Key':
                'lab-${DateTime.now().microsecondsSinceEpoch}-${patient['patientId']}',
          },
        );
        if (context.mounted) {
          context.go('/clinic/laboratory/orders/${o['orderId']}');
        }
      },
      success: 'Order created',
      after: () => _refresh(ref),
    );
  }
}

class LabOrderDetailPage extends ConsumerWidget {
  const LabOrderDetailPage({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/laboratory/orders/$orderId');
    final rq = Query('/laboratory/orders/$orderId/results');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (o) {
        final status = '${o['status']}';
        final external = o['external'] == true;
        final items = ((o['items'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final samples = ((o['samples'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final history = ((o['history'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final manage = can(ref, ClinicPermission.labOrdersManage);
        final collect = can(ref, ClinicPermission.labSamplesManage);
        final enter = can(ref, ClinicPermission.labResultsEnter);
        final verify = can(ref, ClinicPermission.labResultsVerify);
        final publish = can(ref, ClinicPermission.labReportsPublish);
        final ext = can(ref, ClinicPermission.labExternalManage);
        final seeResults = can(ref, ClinicPermission.labResultsView);

        Future<void> post(String path, Map<String, Object?>? body, String ok) =>
            runAction(
              context,
              action: () async => repo.sendMap('POST', path, body ?? {}),
              success: ok,
              after: () => _refresh(ref),
            );

        Future<void> askReason(
          String title,
          String path,
          String ok, {
          String confirm = 'Confirm',
        }) async {
          final v = await showRecordDialog(
            context,
            title: title,
            confirmLabel: confirm,
            fields: const [
              FieldSpec(
                'reason',
                'Reason',
                kind: FieldKind.multiline,
                required: true,
                maxLength: 300,
              ),
            ],
          );
          if (v == null || !context.mounted) return;
          await post(path, v, ok);
        }

        final actions = <Widget>[
          if (manage && status == 'requested') ...[
            sized(
              EcPrimaryButton(
                key: const Key('lab-accept'),
                label: 'Accept',
                onPressed: () =>
                    post('/laboratory/orders/$orderId/accept', {}, 'Accepted'),
              ),
            ),
            sized(
              EcSecondaryButton(
                key: const Key('lab-reject'),
                label: 'Reject',
                onPressed: () => askReason(
                  'Reject this order',
                  '/laboratory/orders/$orderId/reject',
                  'Rejected',
                ),
              ),
            ),
          ],
          if (collect && (status == 'accepted' || status == 'sample_pending'))
            sized(
              EcPrimaryButton(
                key: const Key('lab-add-sample'),
                label: 'Add sample',
                onPressed: () => post(
                  '/laboratory/orders/$orderId/samples',
                  {},
                  'Sample added',
                ),
              ),
            ),
          if (verify && status == 'verification_pending') ...[
            sized(
              EcPrimaryButton(
                key: const Key('lab-verify'),
                label: 'Verify results',
                onPressed: () =>
                    post('/laboratory/orders/$orderId/verify', {}, 'Verified'),
              ),
            ),
            sized(
              EcSecondaryButton(
                key: const Key('lab-return'),
                label: 'Return for correction',
                onPressed: () => askReason(
                  'Return for correction',
                  '/laboratory/orders/$orderId/return',
                  'Returned',
                ),
              ),
            ),
          ],
          if (publish && status == 'verified')
            sized(
              EcPrimaryButton(
                key: const Key('lab-publish'),
                label: 'Publish report',
                onPressed: () => post(
                  '/laboratory/orders/$orderId/publish',
                  {},
                  'Report published',
                ),
              ),
            ),
          if (enter && !external && status == 'processing')
            sized(
              EcPrimaryButton(
                key: const Key('lab-submit'),
                label: 'Submit for verification',
                onPressed: () => post(
                  '/laboratory/orders/$orderId/submit-verification',
                  {},
                  'Submitted for verification',
                ),
              ),
            ),
          if (ext &&
              external &&
              (status == 'sample_collected' || status == 'processing'))
            sized(
              EcPrimaryButton(
                key: const Key('lab-upload-external'),
                label: 'Upload external report',
                onPressed: () => _uploadExternal(context, ref, orderId),
              ),
            ),
          if (manage &&
              const {
                'requested',
                'accepted',
                'sample_pending',
                'recollection_required',
                'sample_collected',
              }.contains(status))
            sized(
              EcSecondaryButton(
                key: const Key('lab-cancel'),
                label: 'Cancel order',
                onPressed: () => askReason(
                  'Cancel this order',
                  '/laboratory/orders/$orderId/cancel',
                  'Order cancelled',
                ),
              ),
            ),
        ];

        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${o['orderNumber']}',
              subtitle:
                  '${o['patientName']} · ${o['patientMrn']} · ${o['branchName']}',
              actions: [statusChip(status)],
            ),
            Section(
              title: 'Order',
              child: KeyValues([
                ('Priority', Fmt.humanize(o['priority'])),
                ('Requested by', o['doctorName'] ?? 'Laboratory desk'),
                ('Created', Fmt.dateTime(o['createdAt'])),
                (
                  'Source',
                  external ? 'External laboratory' : 'In-house laboratory',
                ),
                (
                  'Rejected / cancelled',
                  o['rejectReason'] ?? o['cancelReason'],
                ),
              ]),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: Wrap(
                  spacing: EcSpacing.md,
                  runSpacing: EcSpacing.md,
                  children: actions,
                ),
              ),
            Section(
              title: 'Tests',
              child: Column(
                children: [
                  for (final i in items)
                    ListTile(
                      key: Key('lab-item-${i['itemId']}'),
                      title: Text('${i['name']} (${i['code']})'),
                      subtitle: Text(
                        [
                          Fmt.humanize(i['sampleType']),
                          if (i['fastingRequired'] == true) 'Fasting required',
                          if (i['indication'] != null) '${i['indication']}',
                        ].join(' · '),
                      ),
                      trailing:
                          enter &&
                              !external &&
                              (status == 'sample_collected' ||
                                  status == 'processing')
                          ? TextButton(
                              key: Key('enter-${i['itemId']}'),
                              onPressed: () =>
                                  _enterResults(context, ref, orderId, i, rq),
                              child: const Text('Enter results'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Section(
              title: 'Samples',
              child: samples.isEmpty
                  ? const Text('No samples yet.')
                  : Column(
                      children: [
                        for (final s in samples)
                          _SampleTile(
                            sample: s,
                            orderId: orderId,
                            canManage: collect,
                          ),
                      ],
                    ),
            ),
            if (seeResults && !external)
              _ResultsSection(
                orderId: orderId,
                orderStatus: status,
                canAmend: enter,
                items: items,
              ),
            if (ext || status == 'published' || external)
              _ReportsSection(orderId: orderId),
            Section(
              title: 'History',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['status'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['role']}${h['reason'] == null ? '' : ' · ${h['reason']}'}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadExternal(
    BuildContext context,
    WidgetRef ref,
    String orderId,
  ) async {
    final pick = ref.read(externalReportPickerProvider);
    final repo = ref.read(controlPlaneRepositoryProvider);
    final f = await pick();
    if (f == null || !context.mounted) return;
    await runAction(
      context,
      action: () async => repo.sendMap(
        'POST',
        '/laboratory/orders/$orderId/external-report',
        {'fileName': f.name, 'contentBase64': base64.encode(f.bytes)},
      ),
      success:
          'Report uploaded. A colleague must review it before it is published.',
      after: () => _refresh(ref),
    );
  }

  Future<void> _enterResults(
    BuildContext context,
    WidgetRef ref,
    String orderId,
    Map<String, Object?> item,
    Query results,
  ) async {
    final repo = ref.read(controlPlaneRepositoryProvider);
    final existing = await repo.getMap('/laboratory/orders/$orderId/results');
    if (!context.mounted) return;
    final cur = ((existing['results'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .where((r) => r['itemId'] == item['itemId']);
    final obs = cur.isEmpty
        ? const <Map<String, Object?>>[]
        : ((cur.first['observations'] as List?) ?? const [])
              .cast<Map<String, Object?>>();
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ResultDialog(item: item, existing: obs),
    );
    if (body == null || !context.mounted) return;
    await runAction(
      context,
      action: () async => repo.sendMap(
        'PUT',
        '/laboratory/orders/$orderId/results/${item['itemId']}',
        body,
      ),
      success: 'Results saved as a draft',
      after: () => _refresh(ref),
    );
  }
}

class _SampleTile extends ConsumerWidget {
  const _SampleTile({
    required this.sample,
    required this.orderId,
    required this.canManage,
  });

  final Map<String, Object?> sample;
  final String orderId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(controlPlaneRepositoryProvider);
    final id = '${sample['sampleId']}';
    final status = '${sample['status']}';
    Future<void> collect() async {
      final v = await showRecordDialog(
        context,
        title: 'Collect sample ${sample['sampleNumber']}',
        confirmLabel: 'Record collection',
        note:
            'Check the patient\'s identity first: ask them to confirm their name and enter the patient number printed on their card.',
        fields: const [
          FieldSpec(
            'confirmedMrn',
            'Patient number (confirm identity)',
            required: true,
            maxLength: 30,
          ),
          FieldSpec(
            'identifier',
            'Sample label / barcode',
            required: true,
            maxLength: 40,
          ),
          FieldSpec(
            'notes',
            'Notes',
            kind: FieldKind.multiline,
            maxLength: 300,
          ),
        ],
      );
      if (v == null || !context.mounted) return;
      await runAction(
        context,
        action: () async =>
            repo.sendMap('POST', '/laboratory/samples/$id/collect', v),
        success: 'Sample collected',
        after: () => _refresh(ref),
      );
    }

    Future<void> reject() async {
      final v = await showRecordDialog(
        context,
        title: 'Reject sample ${sample['sampleNumber']}',
        confirmLabel: 'Reject sample',
        fields: const [
          FieldSpec(
            'reason',
            'Reason',
            kind: FieldKind.multiline,
            required: true,
            maxLength: 300,
          ),
        ],
      );
      if (v == null || !context.mounted) return;
      await runAction(
        context,
        action: () async =>
            repo.sendMap('POST', '/laboratory/samples/$id/reject', v),
        success: 'Sample rejected. Recollection is required.',
        after: () => _refresh(ref),
      );
    }

    return ListTile(
      key: Key('sample-$id'),
      title: Text(
        '${sample['sampleNumber']} · ${Fmt.humanize(sample['sampleType'])}',
      ),
      subtitle: Text(
        [
          if (sample['identifier'] != null) 'Label ${sample['identifier']}',
          if (sample['collectedAt'] != null)
            'Collected ${Fmt.dateTime(sample['collectedAt'])}',
          if (sample['rejectReason'] != null) '${sample['rejectReason']}',
        ].join(' · '),
      ),
      leading: statusChip(status),
      trailing: !canManage
          ? null
          : Wrap(
              spacing: EcSpacing.xs,
              children: [
                if (status == 'pending')
                  TextButton(
                    key: Key('collect-$id'),
                    onPressed: collect,
                    child: const Text('Collect'),
                  ),
                if (status == 'pending' || status == 'collected')
                  TextButton(
                    key: Key('reject-sample-$id'),
                    onPressed: reject,
                    child: const Text('Reject'),
                  ),
                if (status == 'rejected' && sample['recollectedAs'] == null)
                  TextButton(
                    key: Key('recollect-$id'),
                    onPressed: () => runAction(
                      context,
                      action: () async => repo.sendMap(
                        'POST',
                        '/laboratory/samples/$id/recollect',
                        {},
                      ),
                      success: 'Recollection requested',
                      after: () => _refresh(ref),
                    ),
                    child: const Text('Request recollection'),
                  ),
              ],
            ),
    );
  }
}

class _ResultDialog extends StatefulWidget {
  const _ResultDialog({required this.item, required this.existing});

  final Map<String, Object?> item;
  final List<Map<String, Object?>> existing;

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  late final List<Map<String, Object?>> _params;
  final Map<String, TextEditingController> _c = {};
  final Map<String, String?> _choice = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _params = ((widget.item['parameters'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    for (final p in _params) {
      final code = '${p['code']}';
      final prior = widget.existing.where((o) => o['code'] == code);
      final value = prior.isEmpty ? null : prior.first['value'];
      if (p['valueType'] == 'qualitative') {
        _choice[code] = value as String?;
      } else {
        _c[code] = TextEditingController(text: value == null ? '' : '$value');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final obs = <Map<String, Object?>>[];
    for (final p in _params) {
      final code = '${p['code']}';
      if (p['valueType'] == 'qualitative') {
        final v = _choice[code];
        if (v != null) obs.add({'code': code, 'value': v});
      } else {
        final t = _c[code]!.text.trim();
        if (t.isEmpty) continue;
        if (p['valueType'] == 'numeric') {
          final n = num.tryParse(t);
          if (n == null) {
            setState(() => _error = '${p['name']} must be a number.');
            return;
          }
          obs.add({'code': code, 'value': n});
        } else {
          obs.add({'code': code, 'value': t});
        }
      }
    }
    if (obs.isEmpty) {
      setState(() => _error = 'Enter at least one value.');
      return;
    }
    Navigator.of(context).pop({'observations': obs});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Results: ${widget.item['name']}'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              EcInlineMessage(tone: EcStatusTone.error, message: _error!),
            for (final p in _params)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.md),
                child: p['valueType'] == 'qualitative'
                    ? DropdownButtonFormField<String>(
                        key: Key('param-${p['code']}'),
                        value: _choice['${p['code']}'],
                        decoration: InputDecoration(labelText: '${p['name']}'),
                        items: [
                          for (final o
                              in ((p['qualitativeOptions'] as List?) ??
                                      const [])
                                  .cast<Map<String, Object?>>())
                            DropdownMenuItem(
                              value: '${o['value']}',
                              child: Text('${o['value']}'),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _choice['${p['code']}'] = v),
                      )
                    : TextField(
                        key: Key('param-${p['code']}'),
                        controller: _c['${p['code']}'],
                        decoration: InputDecoration(
                          labelText:
                              '${p['name']}${p['unit'] == null ? '' : ' (${p['unit']})'}',
                        ),
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
      FilledButton(
        key: const Key('save-results'),
        onPressed: _save,
        child: const Text('Save draft'),
      ),
    ],
  );
}

class _ResultsSection extends ConsumerWidget {
  const _ResultsSection({
    required this.orderId,
    required this.orderStatus,
    required this.canAmend,
    required this.items,
  });

  final String orderId;
  final String orderStatus;
  final bool canAmend;
  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/laboratory/orders/$orderId/results');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final results = ((d['results'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        if (results.isEmpty) return const SizedBox.shrink();
        return Section(
          title: 'Results',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in results) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r['testName']}',
                        style: EcTypography.bodyStrong,
                      ),
                    ),
                    statusChip(r['status']),
                    if (canAmend &&
                        (orderStatus == 'verified' ||
                            orderStatus == 'published'))
                      TextButton(
                        key: Key('amend-${r['itemId']}'),
                        onPressed: () => _amend(context, ref, repo, r),
                        child: const Text('Amend'),
                      ),
                  ],
                ),
                for (final o
                    in ((r['observations'] as List?) ?? const [])
                        .cast<Map<String, Object?>>())
                  ListTile(
                    dense: true,
                    title: Text(
                      '${o['name']}: ${o['value']}${o['unit'] == null ? '' : ' ${o['unit']}'}',
                    ),
                    subtitle: Text(_rangeText(o['range'])),
                    trailing:
                        flagLabel(o['flag']).isEmpty || o['flag'] == 'normal'
                        ? null
                        : Text(
                            flagLabel(o['flag']),
                            key: Key('flag-${o['code']}'),
                            style: EcTypography.bodyStrong.copyWith(
                              color: flagColor(o['flag']),
                            ),
                          ),
                  ),
                if (r['revision'] != null && (r['revision']! as int) > 1)
                  Text(
                    'Amended: revision ${r['revision']}. ${r['amendReason'] ?? ''}',
                    style: EcTypography.bodySecondary,
                  ),
                const Divider(),
              ],
            ],
          ),
        );
      },
    );
  }

  String _rangeText(Object? range) {
    if (range is! Map) return 'No reference range configured';
    final lo = range['low'];
    final hi = range['high'];
    final u = range['unit'] == null ? '' : ' ${range['unit']}';
    final span = lo != null && hi != null
        ? '$lo – $hi$u'
        : hi != null
        ? 'up to $hi$u'
        : lo != null
        ? 'from $lo$u'
        : '';
    return 'Reference $span${range['source'] == null ? '' : ' (${range['source']})'}';
  }

  Future<void> _amend(
    BuildContext context,
    WidgetRef ref,
    ControlPlaneRepository repo,
    Map<String, Object?> r,
  ) async {
    final item = items.firstWhere((i) => i['itemId'] == r['itemId']);
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ResultDialog(
        item: item,
        existing: ((r['observations'] as List?) ?? const [])
            .cast<Map<String, Object?>>(),
      ),
    );
    if (body == null || !context.mounted) return;
    final reason = await showRecordDialog(
      context,
      title: 'Why is this being amended?',
      confirmLabel: 'Amend',
      note:
          'The previous values are kept. The amended results must be verified by someone else before the report is republished.',
      fields: const [
        FieldSpec(
          'reason',
          'Reason',
          kind: FieldKind.multiline,
          required: true,
          maxLength: 300,
        ),
      ],
    );
    if (reason == null || !context.mounted) return;
    await runAction(
      context,
      action: () async => repo.sendMap(
        'POST',
        '/laboratory/orders/$orderId/results/${r['itemId']}/amend',
        {...body, ...reason},
      ),
      success: 'Amendment saved. Verification is required.',
      after: () => _refresh(ref),
    );
  }
}

class _ReportsSection extends ConsumerWidget {
  const _ReportsSection({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/laboratory/reports', {'orderId': orderId});
    if (!can(ref, ClinicPermission.labReportsView)) {
      return const SizedBox.shrink();
    }
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return Section(
          title: 'Reports',
          child: Column(
            children: [
              for (final r in rows)
                ListTile(
                  key: Key('report-${r['reportId']}'),
                  title: Text('${r['reportNumber']} · version ${r['version']}'),
                  subtitle: Text(
                    [
                      '${r['label'] ?? ''}',
                      if (r['external'] == true &&
                          r['verifiedByClinic'] != true)
                        'Not yet reviewed by this clinic',
                      if (r['publishedAt'] != null)
                        'Published ${Fmt.dateTime(r['publishedAt'])}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  leading: statusChip(r['status']),
                  trailing: TextButton(
                    key: Key('download-${r['reportId']}'),
                    onPressed: () => runAction(
                      context,
                      action: () async {
                        final bytes = await ref
                            .read(controlPlaneRepositoryProvider)
                            .reportBytes('${r['reportId']}');
                        await ref.read(reportSaverProvider)(
                          '${r['reportNumber']}.${r['contentType'] == 'application/pdf' ? 'pdf' : 'bin'}',
                          bytes,
                        );
                      },
                      success: 'Report downloaded',
                    ),
                    child: const Text('Download'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- catalogue

class LabTestsPage extends ConsumerWidget {
  const LabTestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manage = can(ref, ClinicPermission.labTestsManage);
    return ListScreen(
      title: 'Laboratory tests',
      subtitle:
          'The catalogue. Reference ranges are set by this clinic and always carry their source.',
      path: '/laboratory/tests',
      statusOptions: const ['active', 'inactive'],
      searchHint: 'Test name',
      extraDropdown: (
        'Category',
        'category',
        const [
          'hematology',
          'biochemistry',
          'clinical_pathology',
          'microbiology',
          'serology',
          'immunology',
          'other',
        ],
      ),
      emptyTitle: 'No tests yet',
      emptyMessage: 'Add the tests your laboratory offers.',
      actions: [
        if (manage)
          sized(
            EcPrimaryButton(
              key: const Key('new-lab-test'),
              label: 'Add test',
              onPressed: () => _create(context, ref),
            ),
          ),
      ],
      rowBuilder: (context, r) => RowCard(
        title: '${r['code']} · ${r['name']}',
        subtitle:
            '${Fmt.humanize(r['category'])} · ${Fmt.humanize(r['sampleType'])} · ${r['turnaroundHours']} h'
            '${r['priceMinor'] == null ? '' : ' · ${Fmt.money(r['priceMinor'])}'}',
        status: r['status'],
        onTap: () {},
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final v = await showRecordDialog(
      context,
      title: 'Add a laboratory test',
      confirmLabel: 'Add test',
      note:
          'This form adds a test with one measured value. Use the reference range fields only with figures approved by your laboratory.',
      fields: const [
        FieldSpec('code', 'Code', required: true, maxLength: 20),
        FieldSpec('name', 'Name', required: true, maxLength: 120),
        FieldSpec(
          'category',
          'Category',
          kind: FieldKind.choice,
          required: true,
          options: [
            'hematology',
            'biochemistry',
            'clinical_pathology',
            'microbiology',
            'serology',
            'immunology',
            'other',
          ],
        ),
        FieldSpec(
          'sampleType',
          'Sample type',
          kind: FieldKind.choice,
          required: true,
          options: [
            'blood',
            'serum',
            'plasma',
            'urine',
            'stool',
            'swab',
            'sputum',
            'tissue',
            'csf',
            'other',
          ],
        ),
        FieldSpec('turnaroundHours', 'Turnaround (hours)', required: true),
        FieldSpec('price', 'Price (₹)', kind: FieldKind.money),
        FieldSpec('paramName', 'Measured value name', required: true),
        FieldSpec('unit', 'Unit', maxLength: 20),
        FieldSpec('low', 'Reference low', maxLength: 12),
        FieldSpec('high', 'Reference high', maxLength: 12),
        FieldSpec('source', 'Reference source', maxLength: 120),
      ],
    );
    if (v == null || !context.mounted) return;
    final tat = int.tryParse('${v['turnaroundHours']}');
    final low = num.tryParse('${v['low'] ?? ''}');
    final high = num.tryParse('${v['high'] ?? ''}');
    final price = v['price'] == null ? null : parseMinor('${v['price']}');
    if (tat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnaround must be a whole number.')),
      );
      return;
    }
    final unit = v['unit'] == null ? null : '${v['unit']}';
    await runAction(
      context,
      action: () async => ref.read(controlPlaneRepositoryProvider).sendMap(
        'POST',
        '/laboratory/tests',
        {
          'code': v['code'],
          'name': v['name'],
          'category': v['category'],
          'sampleType': v['sampleType'],
          'turnaroundHours': tat,
          'priceMinor': ?price,
          'parameters': [
            {
              'code': 'V1',
              'name': v['paramName'],
              'valueType': 'numeric',
              'unit': ?unit,
              if (low != null || high != null)
                'referenceRanges': [
                  {
                    'low': ?low,
                    'high': ?high,
                    'unit': ?unit,
                    'source': v['source'] ?? 'Clinic laboratory',
                  },
                ],
            },
          ],
        },
      ),
      success: 'Test added',
      after: () => _refresh(ref),
    );
  }
}

// ----------------------------------------------------------- external labs

class LabExternalLabsPage extends ConsumerWidget {
  const LabExternalLabsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/laboratory/external-labs');
    final manage = can(ref, ClinicPermission.labExternalManage);
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (labs) {
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'External laboratories',
              subtitle:
                  'Laboratories that run tests this clinic does not. Their reports are labelled as external.',
              actions: [
                if (manage)
                  sized(
                    EcPrimaryButton(
                      key: const Key('new-external-lab'),
                      label: 'Add laboratory',
                      onPressed: () async {
                        final v = await showRecordDialog(
                          context,
                          title: 'Add an external laboratory',
                          fields: const [
                            FieldSpec('name', 'Name', required: true),
                            FieldSpec('contactPerson', 'Contact person'),
                            FieldSpec('phone', 'Phone', maxLength: 20),
                            FieldSpec('email', 'Email'),
                          ],
                        );
                        if (v == null || !context.mounted) return;
                        await runAction(
                          context,
                          action: () async => repo.sendMap(
                            'POST',
                            '/laboratory/external-labs',
                            v,
                          ),
                          success: 'Laboratory added',
                          after: () => _refresh(ref),
                        );
                      },
                    ),
                  ),
              ],
            ),
            if (labs.isEmpty)
              const EcCard(child: Text('No external laboratories yet.')),
            for (final l in labs)
              EcCard(
                child: ListTile(
                  title: Text('${l['name']}'),
                  subtitle: Text(
                    [
                      if (l['contactPerson'] != null) '${l['contactPerson']}',
                      if (l['phone'] != null) '${l['phone']}',
                    ].join(' · '),
                  ),
                  trailing: statusChip(l['status']),
                ),
              ),
          ],
        );
      },
    );
  }
}
