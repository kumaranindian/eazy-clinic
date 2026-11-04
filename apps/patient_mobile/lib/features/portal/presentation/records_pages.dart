import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/portal_repository.dart';
import 'common_widgets.dart';
import 'lab_reports.dart';
import 'providers.dart';
import 'ui_kit.dart';

const _tabs = <(String, String)>[
  ('overview', 'Overview'),
  ('visits', 'Visits'),
  ('prescriptions', 'Prescriptions'),
  ('bills', 'Bills'),
  ('reports', 'Lab reports'),
  ('documents', 'Documents'),
];

/// Medical overview, released visit summaries, prescriptions, bills and
/// documents of the selected person. Read-only: nothing here edits a record.
class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({this.initialTab = 'overview', super.key});

  final String initialTab;

  @override
  ConsumerState<RecordsPage> createState() => _RecordsState();
}

class _RecordsState extends ConsumerState<RecordsPage> {
  late String _tab = _tabs.any((t) => t.$1 == widget.initialTab)
      ? widget.initialTab
      : 'overview';

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(selectedPersonProvider);
    final p = forPerson(person);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Medical records',
          subtitle: 'Only what your clinics have shared with you.',
        ),
        const PersonBar(),
        Wrap(
          spacing: EcSpacing.sm,
          children: [
            for (final t in _tabs)
              ChoiceChip(
                key: Key('tab-${t.$1}'),
                label: Text(t.$2),
                selected: _tab == t.$1,
                onSelected: (_) => setState(() => _tab = t.$1),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.md),
        switch (_tab) {
          'visits' => _Visits(params: p),
          'prescriptions' => _Prescriptions(params: p),
          'bills' => _Bills(params: p),
          'reports' => LabReports(params: p),
          'documents' => const _Documents(),
          _ => _Overview(params: p),
        },
      ],
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.params});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/medical-records', params);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (clinics) {
        if (clinics.isEmpty) return const LinkClinicHint();
        return Column(
          children: [
            for (final c in clinics) ...[
              Section(
                title: '${c['clinicName'] ?? 'Clinic'}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _list(
                      'Allergies',
                      c['allergies'],
                      (a) =>
                          '${a['allergen']}${a['severity'] == null ? '' : ' · ${humanize(a['severity'])}'}${a['reaction'] == null ? '' : ' · ${a['reaction']}'}',
                    ),
                    _list(
                      'Conditions and history',
                      c['history'],
                      (h) => '${h['title']} · ${humanize(h['category'])}',
                    ),
                    _list(
                      'Medicines recorded',
                      c['medications'],
                      (m) =>
                          '${m['name']}${m['dosage'] == null ? '' : ' · ${m['dosage']}'}${m['frequency'] == null ? '' : ' · ${m['frequency']}'}',
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _list(String title, Object? rows, String Function(Json) line) {
    final items = ((rows as List?) ?? const []).cast<Json>();
    return Padding(
      padding: const EdgeInsets.only(bottom: EcSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: EcTypography.bodyStrong),
          if (items.isEmpty)
            const Text('Nothing recorded.')
          else
            for (final i in items) Text('• ${line(i)}'),
        ],
      ),
    );
  }
}

class _Visits extends ConsumerWidget {
  const _Visits({required this.params});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/consultations', params);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (rows) => rows.isEmpty
          ? const EcEmptyState(
              title: 'No visit summaries yet',
              message: 'Your doctor can share a summary after a visit.',
              icon: Icons.description_outlined,
            )
          : Column(
              children: [
                for (final c in rows)
                  Section(
                    title:
                        '${shortDate(c['consultationAt'])} · ${c['doctorName'] ?? ''}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d
                            in ((c['diagnoses'] as List?) ?? const [])
                                .cast<Json>())
                          Text(
                            '${d['label']} (${humanize(d['certainty'])})',
                            style: EcTypography.bodyStrong,
                          ),
                        KeyValues([
                          ('Advice', (c['advice'] as Map?)?['recommendations']),
                          (
                            'Instructions',
                            (c['advice'] as Map?)?['patientInstructions'],
                          ),
                          ('Diet', (c['advice'] as Map?)?['diet']),
                          (
                            'Follow-up on',
                            (c['followUp'] as Map?)?['recommendedDate'],
                          ),
                          (
                            'Follow-up note',
                            (c['followUp'] as Map?)?['reason'],
                          ),
                          (
                            'Prescription',
                            ((c['prescriptions'] as List?) ?? const [])
                                .map((p) => (p as Map)['number'])
                                .join(', '),
                          ),
                        ]),
                        if (c['amended'] == true)
                          Text(
                            'Updated by your doctor after the visit.',
                            style: EcTypography.bodySecondary,
                          ),
                        Text(
                          c['clinicName'] == null ? '' : '${c['clinicName']}',
                          style: EcTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Prescriptions extends ConsumerWidget {
  const _Prescriptions({required this.params});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/prescriptions', params);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (rows) => rows.isEmpty
          ? const EcEmptyState(
              title: 'No prescriptions',
              message: 'Prescriptions your doctor issues appear here.',
              icon: Icons.medication_outlined,
            )
          : Column(
              children: [
                for (final r in rows)
                  Section(
                    title: '${r['number']} · ${shortDate(r['issuedAt'])}',
                    trailing: statusChip(
                      r['current'] == true ? 'current' : 'superseded',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['doctorName'] ?? ''} · ${r['clinicName'] ?? ''}',
                          style: EcTypography.bodySecondary,
                        ),
                        if (r['superseded'] == true)
                          const Text(
                            'Replaced by a newer version. Shown for your history.',
                          ),
                        for (final m
                            in ((r['medicines'] as List?) ?? const [])
                                .cast<Json>())
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${m['name']} ${m['strength'] ?? ''}'.trim(),
                            ),
                            subtitle: Text(
                              '${m['dosage']} · ${m['frequency']} · ${m['durationValue']} ${m['durationUnit']}'
                              '${m['route'] == null ? '' : ' · ${m['route']}'}'
                              '${m['instructions'] == null ? '' : '\n${m['instructions']}'}'
                              '${m['warnings'] == null ? '' : '\nNote: ${m['warnings']}'}',
                            ),
                          ),
                        Text(
                          '${r['disclaimer']}',
                          style: EcTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Bills extends ConsumerWidget {
  const _Bills({required this.params});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = Query('/patient/invoices', params);
    final pay = Query('/patient/payments', params);
    final rf = Query('/patient/refunds', params);
    final sum = Query('/patient/billing-summary', params);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncBody(
          value: ref.watch(listProvider(sum)),
          onRetry: () => ref.invalidate(listProvider(sum)),
          builder: (rows) => Section(
            title: 'Balance',
            child: rows.isEmpty
                ? const Text('No clinic linked.')
                : Column(
                    children: [
                      for (final s in rows)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${s['clinicName']}'),
                          subtitle: Text(
                            'Advance credit ${money(s['creditBalance'])}',
                          ),
                          trailing: Text(
                            'Due ${money(s['outstanding'])}',
                            key: Key('due-${s['clinicId']}'),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        AsyncBody(
          value: ref.watch(listProvider(inv)),
          onRetry: () => ref.invalidate(listProvider(inv)),
          builder: (rows) => Section(
            title: 'Invoices',
            child: rows.isEmpty
                ? const Text('No invoices.')
                : Column(
                    children: [
                      for (final i in rows)
                        ListTile(
                          key: Key('invoice-${i['invoiceId']}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${i['invoiceNumber']} · ${shortDate(i['invoiceDate'])}',
                          ),
                          subtitle: Text(
                            '${i['clinicName'] ?? ''} · due ${money(i['outstanding'], i['currency'])}',
                          ),
                          trailing: statusChip(
                            i['displayStatus'] ?? i['status'],
                          ),
                          onTap: () => context.go(
                            '/records/invoices/${i['clinicId']}/${i['invoiceId']}${params.containsKey('accountId') ? '?accountId=${params['accountId']}' : ''}',
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        AsyncBody(
          value: ref.watch(listProvider(pay)),
          onRetry: () => ref.invalidate(listProvider(pay)),
          builder: (rows) => Section(
            title: 'Payments',
            child: rows.isEmpty
                ? const Text('No payments.')
                : Column(
                    children: [
                      for (final p in rows)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${money(p['amount'], p['currency'])} · ${humanize(p['method'])}',
                          ),
                          subtitle: Text(
                            '${shortDateTime(p['receivedAt'])} · receipt ${p['receiptNumber']}',
                          ),
                          trailing: const Icon(Icons.receipt_long_outlined),
                          onTap: () => _receipt(context, ref, p),
                        ),
                    ],
                  ),
          ),
        ),
        AsyncBody(
          value: ref.watch(listProvider(rf)),
          onRetry: () => ref.invalidate(listProvider(rf)),
          builder: (rows) => rows.isEmpty
              ? const SizedBox.shrink()
              : Section(
                  title: 'Refunds',
                  child: Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(money(r['amount'], r['currency'])),
                          subtitle: Text(
                            '${r['invoiceNumber'] ?? 'Advance'} · ${shortDate(r['requestedAt'])}',
                          ),
                          trailing: statusChip(r['status']),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _receipt(BuildContext context, WidgetRef ref, Json p) async {
    final r = await ref
        .read(portalRepositoryProvider)
        .getMap(
          '/patient/clinics/${p['clinicId']}/receipts/${p['receiptId']}',
          params,
        );
    if (!context.mounted) return;
    final clinic = (r['clinic'] as Map?) ?? const {};
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Receipt ${r['receiptNumber']}'),
        content: SingleChildScrollView(
          child: KeyValues([
            ('Clinic', clinic['name']),
            ('Date', shortDateTime(r['receivedAt'])),
            ('Amount', money(r['amount'], r['currency'])),
            ('Method', humanize(r['method'])),
            ('Reference', r['reference']),
            (
              'Applied to',
              ((r['invoices'] as List?) ?? const [])
                  .map((i) => (i as Map)['invoiceNumber'])
                  .join(', '),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class InvoicePage extends ConsumerWidget {
  const InvoicePage({
    required this.clinicId,
    required this.invoiceId,
    this.accountId,
    super.key,
  });

  final String clinicId;
  final String invoiceId;
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query(
      '/patient/clinics/$clinicId/invoices/$invoiceId',
      forPerson(accountId),
    );
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (i) {
        String m(Object? v) => money(v, i['currency']);
        final lines = ((i['lines'] as List?) ?? const []).cast<Json>();
        final pays = ((i['payments'] as List?) ?? const []).cast<Json>();
        final online = (i['onlinePayment'] as Map?) ?? const {};
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Invoice ${i['invoiceNumber']}',
              subtitle:
                  '${i['clinicName'] ?? ''} · ${shortDate(i['invoiceDate'])}',
              actions: [statusChip(i['displayStatus'] ?? i['status'])],
            ),
            Section(
              title: 'Items',
              child: Column(
                children: [
                  for (final l in lines)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${l['description']}'),
                      subtitle: Text('${l['quantity']} × ${m(l['unitMinor'])}'),
                      trailing: Text(m(l['total'])),
                    ),
                ],
              ),
            ),
            Section(
              title: 'Total',
              child: KeyValues([
                ('Subtotal', m(i['subtotal'])),
                ('Discount', m(i['discountTotal'])),
                ('Tax', m(i['taxTotal'])),
                ('Total', m(i['adjustedTotal'] ?? i['grandTotal'])),
                ('Paid', m(i['amountPaid'])),
                (
                  'Refunded',
                  (i['amountRefunded'] ?? 0) == 0
                      ? null
                      : m(i['amountRefunded']),
                ),
                ('Due', m(i['outstanding'])),
                ('Due date', i['dueDate']),
              ]),
            ),
            if (pays.isNotEmpty)
              Section(
                title: 'Payments received',
                child: Column(
                  children: [
                    for (final p in pays)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m(p['amount'])),
                        subtitle: Text(shortDateTime(p['createdAt'])),
                      ),
                  ],
                ),
              ),
            if (((i['outstanding'] as int?) ?? 0) > 0)
              EcInlineMessage(
                tone: EcStatusTone.info,
                message: online['available'] == true
                    ? 'You can pay online.'
                    : '${online['note'] ?? 'Pay at the clinic.'}',
              ),
          ],
        );
      },
    );
  }
}

class _Documents extends ConsumerWidget {
  const _Documents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/documents');
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) => EcEmptyState(
        title: 'Documents are not available yet',
        message:
            '${d['note'] ?? 'Reports and documents will appear here when your clinic shares them.'}',
        icon: Icons.folder_off_outlined,
      ),
    );
  }
}
