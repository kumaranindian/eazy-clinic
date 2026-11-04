import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../finance/finance_kit.dart';
import '../laboratory/lab_pages.dart' show reportSaverProvider;
import '../scheduling/scheduling_providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

const _kinds = [
  ('appointments', 'Appointments'),
  ('queues', 'Queues'),
  ('patients', 'Patients'),
  ('consultations', 'Consultations'),
  ('laboratory', 'Laboratory'),
  ('billing', 'Billing'),
];

String _pct(Object? v) =>
    v is num ? '${(v * 100).toStringAsFixed(1)}%' : 'Not enough data';

/// Date range filters shared by the report screens.
class _RangeBar extends StatefulWidget {
  const _RangeBar({
    required this.from,
    required this.to,
    required this.onApply,
  });

  final String from;
  final String to;
  final void Function(String from, String to) onApply;

  @override
  State<_RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<_RangeBar> {
  late final _f = TextEditingController(text: widget.from);
  late final _t = TextEditingController(text: widget.to);

  @override
  void dispose() {
    _f.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: EcSpacing.md,
    runSpacing: EcSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      SizedBox(
        width: 190,
        child: EcTextField(label: 'From (YYYY-MM-DD)', controller: _f),
      ),
      SizedBox(
        width: 190,
        child: EcTextField(label: 'To (YYYY-MM-DD)', controller: _t),
      ),
      sized(
        EcSecondaryButton(
          key: const Key('apply-range'),
          label: 'Apply',
          onPressed: () {
            final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$');
            if (!ok.hasMatch(_f.text.trim()) || !ok.hasMatch(_t.text.trim())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Use dates like 2026-06-01.')),
              );
              return;
            }
            widget.onApply(_f.text.trim(), _t.text.trim());
          },
        ),
      ),
    ],
  );
}

String _monthStart() {
  final n = DateTime.now();
  return isoDate(DateTime(n.year, n.month, 1));
}

// -------------------------------------------------------------------- dashboard

class ReportsDashboardPage extends ConsumerStatefulWidget {
  const ReportsDashboardPage({super.key});

  @override
  ConsumerState<ReportsDashboardPage> createState() => _DashState();
}

class _DashState extends ConsumerState<ReportsDashboardPage> {
  late String _from = _monthStart();
  late String _to = isoDate(DateTime.now());

  static const _tiles = <String, List<(String, String, String)>>{
    'appointments': [
      ('total', 'Appointments', 'n'),
      ('completed', 'Completed', 'n'),
      ('cancelled', 'Cancelled', 'n'),
      ('noShowRate', 'No-show rate', 'pct'),
    ],
    'queues': [('tokens', 'Queue tokens', 'n')],
    'patients': [
      ('registrations', 'New registrations', 'n'),
      ('activePatients', 'Active patients', 'n'),
    ],
    'consultations': [('total', 'Consultations', 'n')],
    'laboratory': [
      ('ordersCreated', 'Lab orders', 'n'),
      ('reportsPublished', 'Reports published', 'n'),
    ],
    'billing': [
      ('grossBilled', 'Gross billed', 'money'),
      ('collected', 'Collected', 'money'),
      ('refunded', 'Refunded', 'money'),
      (
        'outstandingOnInvoicesInRange',
        'Outstanding on these invoices',
        'money',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(activeBranchProvider);
    final q = Query('/reports/dashboard', {
      'from': _from,
      'to': _to,
      'branchId': branch ?? '',
    });
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Reports',
          subtitle:
              'Figures computed from the clinic\'s own records for the period you choose.',
        ),
        _RangeBar(
          from: _from,
          to: _to,
          onApply: (f, t) => setState(() {
            _from = f;
            _to = t;
          }),
        ),
        const SizedBox(height: EcSpacing.lg),
        AsyncBody(
          value: ref.watch(mapProvider(q)),
          onRetry: () => ref.invalidate(mapProvider(q)),
          builder: (d) {
            final sections = ((d['sections'] as Map?) ?? const {})
                .cast<String, Object?>();
            final trend = d['trend'] as Map?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last updated ${Fmt.dateTime(d['generatedAt'])} · period ${d['from']} to ${d['to']} (${d['timezone']})',
                  key: const Key('freshness'),
                  style: EcTypography.bodySecondary,
                ),
                const SizedBox(height: EcSpacing.md),
                for (final (kind, label) in _kinds)
                  _SectionCard(
                    kind: kind,
                    label: label,
                    section: (sections[kind] as Map?)?.cast<String, Object?>(),
                    tiles: _tiles[kind] ?? const [],
                    from: _from,
                    to: _to,
                  ),
                if (trend != null)
                  Section(
                    title: 'Appointments per day',
                    child: Column(
                      children: [
                        for (final p
                            in (trend['points'] as List)
                                .cast<Map<String, Object?>>())
                          ListTile(
                            dense: true,
                            title: Text('${p['date']}'),
                            trailing: Text('${p['value']}'),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.kind,
    required this.label,
    required this.section,
    required this.tiles,
    required this.from,
    required this.to,
  });

  final String kind;
  final String label;
  final Map<String, Object?>? section;
  final List<(String, String, String)> tiles;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final available = section?['available'] == true;
    final summary = ((section?['summary'] as Map?) ?? const {})
        .cast<String, Object?>();
    return Section(
      title: label,
      trailing: available
          ? TextButton(
              key: Key('open-$kind'),
              onPressed: () =>
                  context.go('/clinic/reports/$kind?from=$from&to=$to'),
              child: const Text('Open report'),
            )
          : null,
      child: !available
          ? Text(
              'Not available for your role or plan.',
              key: Key('unavailable-$kind'),
              style: EcTypography.bodySecondary,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section?['truncated'] == true)
                  const EcInlineMessage(
                    tone: EcStatusTone.warning,
                    message: 'Too many records: these figures are incomplete.',
                  ),
                Wrap(
                  spacing: EcSpacing.md,
                  runSpacing: EcSpacing.md,
                  children: [
                    for (final (k, l, f) in tiles)
                      SizedBox(
                        width: 210,
                        child: EcCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                switch (f) {
                                  'pct' => _pct(summary[k]),
                                  'money' => Fmt.money(summary[k]),
                                  _ => '${summary[k] ?? '—'}',
                                },
                                key: Key('kpi-$kind-$k'),
                                style: EcTypography.sectionTitle,
                              ),
                              Text(l, style: EcTypography.bodySecondary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------- one report

class ReportDetailPage extends ConsumerStatefulWidget {
  const ReportDetailPage({required this.kind, this.from, this.to, super.key});

  final String kind;
  final String? from;
  final String? to;

  @override
  ConsumerState<ReportDetailPage> createState() => _DetailState();
}

class _DetailState extends ConsumerState<ReportDetailPage> {
  late String _from = widget.from ?? _monthStart();
  late String _to = widget.to ?? isoDate(DateTime.now());

  bool _isMoney(String col) =>
      const {'billed', 'collected', 'refunded'}.contains(col);

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(activeBranchProvider);
    final q = Query('/reports/${widget.kind}', {
      'from': _from,
      'to': _to,
      'branchId': branch ?? '',
    });
    final canExport = can(ref, ClinicPermission.reportsExport);
    final repo = ref.read(controlPlaneRepositoryProvider);
    final label = _kinds
        .firstWhere(
          (k) => k.$1 == widget.kind,
          orElse: () => (widget.kind, widget.kind),
        )
        .$2;

    Future<void> export(String format) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final e = await repo.sendMap('POST', '/reports/exports', {
          'report': widget.kind,
          'format': format,
          'from': _from,
          'to': _to,
          if (branch != null) 'branchId': branch,
        });
        final bytes = await repo.exportBytes('${e['exportId']}');
        await ref.read(reportSaverProvider)(
          '${widget.kind}-$_from-$_to.$format',
          bytes,
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Export downloaded. The file link expires in 6 hours.',
            ),
          ),
        );
        ref.invalidate(listProvider);
      } on Object catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(failureText(e)),
            backgroundColor: EcColors.error,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: label,
          subtitle: 'Period $_from to $_to',
          actions: [
            TextButton(
              onPressed: () => context.go('/clinic/reports'),
              child: const Text('All reports'),
            ),
            if (canExport) ...[
              sized(
                EcSecondaryButton(
                  key: const Key('export-csv'),
                  label: 'Export CSV',
                  onPressed: () => export('csv'),
                ),
              ),
              sized(
                EcSecondaryButton(
                  key: const Key('export-pdf'),
                  label: 'Export PDF',
                  onPressed: () => export('pdf'),
                ),
              ),
            ],
          ],
        ),
        _RangeBar(
          from: _from,
          to: _to,
          onApply: (f, t) => setState(() {
            _from = f;
            _to = t;
          }),
        ),
        const SizedBox(height: EcSpacing.lg),
        AsyncBody(
          value: ref.watch(mapProvider(q)),
          onRetry: () => ref.invalidate(mapProvider(q)),
          builder: (d) {
            final cols = ((d['columns'] as List?) ?? const []).cast<String>();
            final rows = ((d['rows'] as List?) ?? const [])
                .cast<Map<String, Object?>>();
            final summary = ((d['summary'] as Map?) ?? const {})
                .cast<String, Object?>();
            final defs = ((d['definitions'] as Map?) ?? const {})
                .cast<String, Object?>();
            final notes = ((d['notes'] as List?) ?? const []).cast<String>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last updated ${Fmt.dateTime(d['generatedAt'])}',
                  key: const Key('freshness'),
                  style: EcTypography.bodySecondary,
                ),
                for (final n in notes)
                  EcInlineMessage(
                    tone: d['truncated'] == true
                        ? EcStatusTone.warning
                        : EcStatusTone.info,
                    message: n,
                  ),
                Section(
                  title: 'Summary',
                  child: KeyValues([
                    for (final e in summary.entries)
                      if (e.value is num ||
                          e.value == null ||
                          e.value is String)
                        (
                          Fmt.humanize(
                            e.key.replaceAllMapped(
                              RegExp('[A-Z]'),
                              (m) => '_${m[0]!.toLowerCase()}',
                            ),
                          ),
                          e.key.toLowerCase().contains('rate')
                              ? _pct(e.value)
                              : (e.value is int &&
                                    widget.kind == 'billing' &&
                                    e.key != 'invoices')
                              ? Fmt.money(e.value)
                              : e.value,
                        ),
                  ]),
                ),
                Section(
                  title: 'Table',
                  child: rows.isEmpty
                      ? const Text(
                          'No records in this period.',
                          key: Key('no-rows'),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              for (final c in cols)
                                DataColumn(label: Text(Fmt.humanize(c))),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(
                                  cells: [
                                    for (final c in cols)
                                      DataCell(
                                        Text(
                                          _isMoney(c) && r[c] is int
                                              ? Fmt.money(r[c])
                                              : '${r[c] ?? ''}',
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                ),
                Section(
                  title: 'How these figures are calculated',
                  child: KeyValues([
                    for (final e in defs.entries)
                      (
                        Fmt.humanize(
                          e.key.replaceAllMapped(
                            RegExp('[A-Z]'),
                            (m) => '_${m[0]!.toLowerCase()}',
                          ),
                        ),
                        e.value,
                      ),
                  ]),
                ),
              ],
            );
          },
        ),
        if (canExport) const _ExportHistory(),
      ],
    );
  }
}

class _ExportHistory extends ConsumerWidget {
  const _ExportHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/reports/exports', const {'limit': '10'});
    final repo = ref.read(controlPlaneRepositoryProvider);
    return Section(
      title: 'Your recent exports',
      child: AsyncBody(
        value: ref.watch(listProvider(q)),
        onRetry: () => ref.invalidate(listProvider(q)),
        builder: (items) {
          if (items.isEmpty) return const Text('No exports yet.');
          return Column(
            children: [
              for (final e in items)
                ListTile(
                  key: Key('export-${e['exportId']}'),
                  dense: true,
                  title: Text(
                    '${Fmt.humanize(e['report'])} · ${('${e['format']}').toUpperCase()}',
                  ),
                  subtitle: Text(
                    '${Fmt.dateTime(e['requestedAt'])} · ${e['rows'] ?? 0} rows',
                  ),
                  leading: statusChip(
                    e['expired'] == true ? 'expired' : e['status'],
                  ),
                  trailing: e['status'] == 'ready' && e['expired'] != true
                      ? TextButton(
                          key: Key('download-export-${e['exportId']}'),
                          onPressed: () => runAction(
                            context,
                            action: () async {
                              final b = await repo.exportBytes(
                                '${e['exportId']}',
                              );
                              await ref.read(reportSaverProvider)(
                                '${e['report']}.${e['format']}',
                                b,
                              );
                            },
                            success: 'Export downloaded',
                          ),
                          child: const Text('Download'),
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}
