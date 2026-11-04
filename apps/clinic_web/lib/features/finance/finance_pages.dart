import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../patients/dialogs.dart';
import '../scheduling/scheduling_providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'finance_kit.dart';

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

// ---------------------------------------------------------------- dashboard

/// Today, the last 7 days and the month so far. Every figure is aggregated by
/// the backend; the definitions are shown so nobody mistakes collections for
/// profit.
class FinanceDashboardPage extends ConsumerWidget {
  const FinanceDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    final q = Query('/finance/dashboard', {'branchId': branch ?? ''});
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final cur = d['currency'];
        Map<String, Object?> sub(String k) =>
            ((d[k] as Map?) ?? const {}).cast<String, Object?>();
        final today = sub('today');
        final week = sub('last7Days');
        final month = sub('monthToDate');
        final out = sub('outstanding');
        final methods = sub('paymentMethods');
        final branches = ((d['branchWise'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final doctors = ((d['doctorWise'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        Widget tiles(List<MoneyTile> t) =>
            Wrap(spacing: EcSpacing.md, runSpacing: EcSpacing.md, children: t);
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Finance',
              subtitle:
                  'As of ${d['asOf']}. Collections are money received, not profit.',
              actions: [
                if (d['truncated'] == true)
                  const EcStatusChip(
                    label: 'Partial data: narrow the period',
                    tone: EcStatusTone.warning,
                  ),
              ],
            ),
            Section(
              title: 'Today',
              child: tiles([
                MoneyTile(
                  'Collected',
                  today['collected'],
                  currency: cur,
                  tileKey: 'today-collected',
                ),
                MoneyTile(
                  'Refunded',
                  today['refunded'],
                  currency: cur,
                  tileKey: 'today-refunded',
                ),
                MoneyTile(
                  'Net collected',
                  today['netCollected'],
                  currency: cur,
                  tileKey: 'today-net',
                ),
              ]),
            ),
            Section(
              title: 'Last 7 days',
              child: tiles([
                MoneyTile('Collected', week['collected'], currency: cur),
                MoneyTile('Refunded', week['refunded'], currency: cur),
                MoneyTile('Net collected', week['netCollected'], currency: cur),
              ]),
            ),
            Section(
              title: 'This month',
              child: tiles([
                MoneyTile(
                  'Invoiced',
                  month['invoiced'],
                  currency: cur,
                  tileKey: 'month-invoiced',
                ),
                MoneyTile('Collected', month['collected'], currency: cur),
                MoneyTile('Refunded', month['refunded'], currency: cur),
                MoneyTile(
                  'Net collected',
                  month['netCollected'],
                  currency: cur,
                ),
                MoneyTile(
                  'Expenses approved',
                  month['expensesApproved'],
                  currency: cur,
                ),
                MoneyTile(
                  'Expenses paid',
                  month['expensesPaid'],
                  currency: cur,
                ),
              ]),
            ),
            Section(
              title: 'Outstanding',
              child: tiles([
                MoneyTile(
                  'Outstanding (${out['invoices']} invoices)',
                  out['total'],
                  currency: cur,
                  tileKey: 'outstanding-total',
                ),
                MoneyTile(
                  'Overdue (${out['overdueInvoices']} invoices)',
                  out['overdueTotal'],
                  currency: cur,
                  tileKey: 'overdue-total',
                ),
              ]),
            ),
            Section(
              title: 'Payment methods this month',
              child: methods.isEmpty
                  ? const Text('No payments this month.')
                  : KeyValues([
                      for (final e in methods.entries)
                        (Fmt.humanize(e.key), Fmt.money(e.value, cur)),
                    ]),
            ),
            Section(
              title: 'Branch-wise this month',
              child: branches.isEmpty
                  ? const Text('No activity this month.')
                  : Column(
                      children: [
                        for (final b in branches)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${b['branchName'] == null || '${b['branchName']}'.isEmpty ? b['branchId'] : b['branchName']}',
                            ),
                            subtitle: Text(
                              'Invoiced ${Fmt.money(b['invoiced'], cur)} · refunded ${Fmt.money(b['refunded'], cur)}',
                            ),
                            trailing: Text(Fmt.money(b['collected'], cur)),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Consultation revenue by doctor (billed)',
              child: doctors.isEmpty
                  ? const Text('No consultation lines billed this month.')
                  : Column(
                      children: [
                        for (final r in doctors)
                          ListTile(
                            dense: true,
                            title: Text('${r['doctorId']}'),
                            subtitle: Text(
                              '${r['consultations']} consultation(s)',
                            ),
                            trailing: Text(Fmt.money(r['revenue'], cur)),
                          ),
                      ],
                    ),
            ),
            if (can(ref, ClinicPermission.financeReportsView))
              Align(
                alignment: Alignment.centerLeft,
                child: sized(
                  EcSecondaryButton(
                    label: 'Open reports',
                    icon: Icons.assessment_outlined,
                    onPressed: () => context.go('/clinic/finance/reports'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ services

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manage = can(ref, ClinicPermission.serviceCatalogueManage);
    return ListScreen(
      title: 'Services and charges',
      subtitle:
          'Prices and tax used when billing. Changing a price never alters a finalized invoice.',
      path: '/billing/services',
      searchHint: 'Search services',
      statusOptions: const ['active', 'inactive'],
      emptyTitle: 'No services yet',
      emptyMessage: 'Add consultation fees and other charges to start billing.',
      actions: [
        if (manage)
          sized(
            EcPrimaryButton(
              label: 'New service',
              icon: Icons.add,
              onPressed: () => _editService(context, ref),
            ),
          ),
        if (manage)
          sized(
            EcSecondaryButton(
              label: 'Tax rules',
              onPressed: () => context.go('/clinic/billing/tax-rules'),
            ),
          ),
      ],
      rowBuilder: (context, r) => RowCard(
        title: '${r['name']}',
        subtitle: '${Fmt.humanize(r['category'])} · version ${r['version']}',
        trailing: Fmt.money(r['amountMinor'], r['currency']),
        status: r['status'],
        onTap: () => _serviceDialog(context, ref, r, manage),
      ),
    );
  }
}

Future<void> _serviceDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> s,
  bool manage,
) async {
  final hist = await ref
      .read(controlPlaneRepositoryProvider)
      .getMap('/billing/services/${s['serviceId']}/price-history');
  if (!context.mounted) return;
  final rows = ((hist['history'] as List?) ?? const [])
      .cast<Map<String, Object?>>();
  final edit = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${s['name']}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price history', style: EcTypography.bodyStrong),
            for (final h in rows.reversed)
              ListTile(
                dense: true,
                title: Text(
                  'Version ${h['version']} · ${Fmt.money(h['amountMinor'], h['currency'])}',
                ),
                subtitle: Text(
                  '${Fmt.dateTime(h['changedAt'])}${h['reason'] == null ? '' : ' · ${h['reason']}'}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        if (manage)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Edit'),
          ),
      ],
    ),
  );
  if (edit == true && context.mounted) {
    await _editService(context, ref, existing: s);
  }
}

Future<void> _editService(
  BuildContext context,
  WidgetRef ref, {
  Map<String, Object?>? existing,
}) async {
  final repo = ref.read(controlPlaneRepositoryProvider);
  final rules = (await repo.getList(
    '/billing/tax-rules',
  )).where((r) => r['status'] == 'active').toList();
  if (!context.mounted) return;
  String? ruleName(Object? id) {
    for (final r in rules) {
      if (r['taxRuleId'] == id) return '${r['name']}';
    }
    return null;
  }

  final v = await showRecordDialog(
    context,
    title: existing == null ? 'New service' : 'Edit service',
    note:
        'Tax rates are your clinic\'s configuration. Have your accountant confirm them.',
    initial: {
      if (existing != null) ...{
        'name': existing['name'],
        'category': existing['category'],
        'amount': minorToInput(existing['amountMinor']),
        'description': existing['description'],
        'taxRule': ruleName(existing['taxRuleId']),
        'status': existing['status'],
      },
    },
    fields: [
      const FieldSpec('name', 'Name', required: true, maxLength: 120),
      const FieldSpec(
        'category',
        'Category',
        kind: FieldKind.choice,
        options: [
          'consultation',
          'follow_up_consultation',
          'registration',
          'procedure',
          'diagnostic',
          'laboratory',
          'custom',
        ],
        required: true,
      ),
      const FieldSpec(
        'amount',
        'Default price',
        kind: FieldKind.money,
        required: true,
        maxLength: 12,
      ),
      FieldSpec(
        'taxRule',
        'Tax rule',
        kind: FieldKind.choice,
        options: [for (final r in rules) '${r['name']}'],
      ),
      const FieldSpec(
        'description',
        'Description',
        kind: FieldKind.multiline,
        maxLength: 500,
      ),
      if (existing != null)
        const FieldSpec(
          'status',
          'Status',
          kind: FieldKind.choice,
          options: ['active', 'inactive'],
        ),
    ],
  );
  if (v == null || !context.mounted) return;
  final amount = parseMinor('${v['amount']}');
  if (amount == null) return;
  final rule = rules.where((r) => r['name'] == v['taxRule']);
  final body = <String, Object?>{
    'name': v['name'],
    'category': v['category'],
    'amountMinor': amount,
    'description': ?v['description'],
    if (rule.isNotEmpty) 'taxRuleId': rule.first['taxRuleId'],
    if (existing != null && v['status'] != null) 'status': v['status'],
  };
  await runAction(
    context,
    action: () async => repo.sendMap(
      existing == null ? 'POST' : 'PATCH',
      existing == null
          ? '/billing/services'
          : '/billing/services/${existing['serviceId']}',
      body,
    ),
    success: existing == null ? 'Service added.' : 'Service updated.',
    after: () => _refresh(ref),
  );
}

class TaxRulesPage extends ConsumerWidget {
  const TaxRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/billing/tax-rules');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Tax rules',
          subtitle:
              'The product ships no tax rates. Enter the components your clinic charges and have them confirmed by your accountant or tax advisor.',
          actions: [
            if (can(ref, ClinicPermission.serviceCatalogueManage))
              sized(
                EcPrimaryButton(
                  label: 'New tax rule',
                  icon: Icons.add,
                  onPressed: () async {
                    final v = await showRecordDialog(
                      context,
                      title: 'New tax rule',
                      initial: const {'mode': 'exclusive'},
                      fields: const [
                        FieldSpec(
                          'name',
                          'Name (for example GST 18%)',
                          required: true,
                          maxLength: 60,
                        ),
                        FieldSpec(
                          'c1',
                          'First component name',
                          required: true,
                          maxLength: 30,
                        ),
                        FieldSpec(
                          'r1',
                          'First component rate (%)',
                          required: true,
                          maxLength: 6,
                        ),
                        FieldSpec(
                          'c2',
                          'Second component name (optional)',
                          maxLength: 30,
                        ),
                        FieldSpec(
                          'r2',
                          'Second component rate (%)',
                          maxLength: 6,
                        ),
                        FieldSpec(
                          'mode',
                          'Prices are',
                          kind: FieldKind.choice,
                          options: ['exclusive', 'inclusive'],
                          required: true,
                        ),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    final r1 = parseBps('${v['r1']}');
                    final r2 = v['r2'] == null ? null : parseBps('${v['r2']}');
                    if (r1 == null || (v['r2'] != null && r2 == null)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter rates like 9 or 2.5.'),
                        ),
                      );
                      return;
                    }
                    await runAction(
                      context,
                      action: () async =>
                          repo.sendMap('POST', '/billing/tax-rules', {
                            'name': v['name'],
                            'inclusive': v['mode'] == 'inclusive',
                            'components': [
                              {'name': v['c1'], 'rateBps': r1},
                              if (r2 != null && v['c2'] != null)
                                {'name': v['c2'], 'rateBps': r2},
                            ],
                          }),
                      success: 'Tax rule added.',
                      after: () => _refresh(ref),
                    );
                  },
                ),
              ),
          ],
        ),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? const EcEmptyState(
                  title: 'No tax rules',
                  message:
                      'Services are billed without tax until you add a rule.',
                )
              : Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        title: Text('${r['name']}'),
                        subtitle: Text(
                          '${((r['components'] as List?) ?? const []).map((c) => '${(c as Map)['name']} ${bpsText(c['rateBps'])}').join(' + ')}'
                          ' · ${r['inclusive'] == true ? 'price includes tax' : 'tax added to price'}',
                        ),
                        trailing: statusChip(r['status']),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ reports

const _reports = <(String, String, String)>[
  ('collections', 'Collections', '/finance/reports/collections'),
  ('outstanding', 'Outstanding', '/finance/reports/outstanding'),
  ('refunds', 'Refunds', '/finance/reports/refunds'),
  ('expenses', 'Expenses', '/finance/reports/expenses'),
  ('branch', 'Branch-wise', '/finance/reports/branch-wise'),
  ('doctor', 'Doctor-wise', '/finance/reports/doctor-wise'),
];

const _moneyKeys = {
  'collected',
  'refunded',
  'netCollected',
  'amount',
  'invoiced',
  'revenue',
  'outstanding',
  'overdue',
  'grandTotal',
  'amountPaid',
  'approvedAndPaid',
  'paid',
  'current',
  'days1to30',
  'days31to60',
  'days61to90',
  'over90',
};

String _header(String k) => Fmt.humanize(
  k.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}'),
);

/// The six finance reports with a date range and filters.
class FinanceReportsPage extends ConsumerStatefulWidget {
  const FinanceReportsPage({super.key});

  @override
  ConsumerState<FinanceReportsPage> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<FinanceReportsPage> {
  String _which = 'collections';
  late String _from;
  late String _to;
  final _fromC = TextEditingController();
  final _toC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = isoDate(DateTime(now.year, now.month, 1));
    _to = isoDate(now);
    _fromC.text = _from;
    _toC.text = _to;
  }

  @override
  void dispose() {
    _fromC.dispose();
    _toC.dispose();
    super.dispose();
  }

  bool _validDate(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(activeBranchProvider);
    final path = _reports.firstWhere((r) => r.$1 == _which).$3;
    final q = Query(path, {'from': _from, 'to': _to, 'branchId': branch ?? ''});
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Finance reports',
          subtitle: 'Aggregated by the server for the period you choose.',
        ),
        Wrap(
          spacing: EcSpacing.sm,
          runSpacing: EcSpacing.sm,
          children: [
            for (final r in _reports)
              ChoiceChip(
                key: Key('report-${r.$1}'),
                label: Text(r.$2),
                selected: _which == r.$1,
                onSelected: (_) => setState(() => _which = r.$1),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.md),
        Row(
          children: [
            SizedBox(
              width: 200,
              child: EcTextField(
                label: 'From (YYYY-MM-DD)',
                controller: _fromC,
              ),
            ),
            const SizedBox(width: EcSpacing.md),
            SizedBox(
              width: 200,
              child: EcTextField(label: 'To (YYYY-MM-DD)', controller: _toC),
            ),
            const SizedBox(width: EcSpacing.md),
            sized(
              EcSecondaryButton(
                label: 'Apply',
                onPressed: () {
                  if (!_validDate(_fromC.text.trim()) ||
                      !_validDate(_toC.text.trim())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Use dates like 2026-06-01.'),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _from = _fromC.text.trim();
                    _to = _toC.text.trim();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        AsyncBody(
          value: ref.watch(mapProvider(q)),
          onRetry: () => ref.invalidate(mapProvider(q)),
          builder: (d) => _ReportView(data: d),
        ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.data});

  final Map<String, Object?> data;

  String _cell(String key, Object? v, Object? cur) {
    if (v == null) return '—';
    if (v is int && _moneyKeys.contains(key)) return Fmt.money(v, cur);
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final cur = data['currency'];
    final rows = ((data['rows'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final cols = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!cols.contains(k) && !k.endsWith('Id')) cols.add(k);
      }
    }
    Widget summary(String title, Object? m) {
      if (m is! Map || m.isEmpty) return const SizedBox.shrink();
      return Section(
        title: title,
        child: KeyValues([
          for (final e in m.entries)
            (_header('${e.key}'), _cell('${e.key}', e.value, cur)),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['truncated'] == true)
          const EcInlineMessage(
            tone: EcStatusTone.warning,
            message:
                'Too many records for this period. Narrow the dates for complete figures.',
          ),
        summary('Totals', data['totals']),
        summary('By method', data['byMethod']),
        summary('By status', data['byStatus']),
        summary('By category', data['byCategory']),
        summary('Ageing', data['ageing']),
        Section(
          title: 'Details',
          child: rows.isEmpty
              ? const Text('No records in this period.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final c in cols) DataColumn(label: Text(_header(c))),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          cells: [
                            for (final c in cols)
                              DataCell(Text(_cell(c, r[c], cur))),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
