import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

String _flagLabel(Object? f) => switch ('$f') {
  'low' => 'Low',
  'high' => 'High',
  'abnormal' => 'Abnormal',
  'critical_low' => 'Critical low',
  'critical_high' => 'Critical high',
  'critical' => 'Critical',
  'unit_mismatch' => 'Unit differs from range',
  'not_assessed' => 'No reference range',
  _ => '',
};

/// Laboratory orders of one consultation: what was requested, where each
/// order is, and — only once the laboratory has verified them — the results
/// with the laboratory's own reference ranges. Nothing here changes a
/// finalized consultation; orders are linked to it by reference.
class LabOrdersSection extends ConsumerWidget {
  const LabOrdersSection({
    required this.consultationId,
    required this.open,
    this.legacy = const [],
    super.key,
  });

  final String consultationId;

  /// Whether the consultation still accepts new requests.
  final bool open;

  /// Free-text requests recorded before the catalogue existed.
  final List<Json> legacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/consultations/$consultationId/lab-orders');
    return Section(
      title: 'Laboratory',
      trailing: open
          ? sized(
              EcSecondaryButton(
                key: const Key('order-lab-tests'),
                label: 'Order tests',
                icon: Icons.biotech_outlined,
                onPressed: () => _order(context, ref),
              ),
              220,
            )
          : null,
      child: AsyncBody(
        value: ref.watch(listProvider(q)),
        onRetry: () => ref.invalidate(listProvider(q)),
        builder: (orders) {
          if (orders.isEmpty && legacy.isEmpty) {
            return const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('No laboratory tests requested.'),
            );
          }
          return Column(
            children: [
              for (final o in orders) _OrderTile(order: o),
              for (final i in legacy)
                ListTile(
                  dense: true,
                  title: Text('${i['testName']}'),
                  subtitle: Text(
                    '${humanize(i['priority'])} · recorded as a note, not sent to the laboratory',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _order(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(clinicalRepositoryProvider);
    final tests = await repo.getList('/laboratory/tests', {
      'status': 'active',
      'limit': '100',
    });
    if (!context.mounted) return;
    if (tests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The laboratory catalogue has no tests yet.'),
        ),
      );
      return;
    }
    final v = await showFormDialog(
      context,
      title: 'Order laboratory tests',
      fields: [
        FieldSpec(
          'test',
          'Test',
          kind: FieldKind.choice,
          required: true,
          options: [for (final t in tests) '${t['code']} · ${t['name']}'],
        ),
        const FieldSpec(
          'indication',
          'Clinical indication',
          required: true,
          maxLength: 300,
        ),
        const FieldSpec(
          'priority',
          'Priority',
          kind: FieldKind.choice,
          options: ['routine', 'urgent', 'emergency'],
        ),
      ],
    );
    if (v == null || !context.mounted) return;
    final code = '${v['test']}'.split(' · ').first;
    final test = tests.firstWhere((t) => t['code'] == code);
    await runAction(
      context,
      action: () =>
          repo.send('POST', '/consultations/$consultationId/lab-orders', {
            'priority': v['priority'] ?? 'routine',
            'tests': [
              {'testId': test['testId'], 'indication': v['indication']},
            ],
          }),
      success: 'Laboratory order sent.',
      after: () => refreshAll(ref),
    );
  }
}

class _OrderTile extends ConsumerStatefulWidget {
  const _OrderTile({required this.order});

  final Json order;

  @override
  ConsumerState<_OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends ConsumerState<_OrderTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final id = '${o['orderId']}';
    final status = '${o['status']}';
    final ready = status == 'verified' || status == 'published';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('lab-order-$id'),
          dense: true,
          title: Text(
            '${o['orderNumber']} · ${((o['tests'] as List?) ?? const []).join(', ')}',
          ),
          subtitle: Text(
            '${humanize(o['priority'])} · ${shortDateTime(o['createdAt'])}'
            '${o['external'] == true ? ' · External laboratory' : ''}',
          ),
          trailing: statusChip(status),
          onTap: ready ? () => setState(() => _expanded = !_expanded) : null,
        ),
        if (!ready)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: EcSpacing.md),
            child: Text(
              'Results appear here once the laboratory has verified them.',
              style: EcTypography.bodySecondary,
            ),
          ),
        if (ready && _expanded) _Results(orderId: id),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/laboratory/orders/$orderId/results');
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final results = ((d['results'] as List?) ?? const []).cast<Json>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in results) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(start: EcSpacing.md),
                child: Text('${r['testName']}', style: EcTypography.bodyStrong),
              ),
              for (final o
                  in ((r['observations'] as List?) ?? const []).cast<Json>())
                ListTile(
                  dense: true,
                  title: Text(
                    '${o['name']}: ${o['value']}${o['unit'] == null ? '' : ' ${o['unit']}'}',
                  ),
                  subtitle: o['range'] is Map
                      ? Text(
                          'Reference ${(o['range'] as Map)['low'] ?? ''}–${(o['range'] as Map)['high'] ?? ''} ${(o['range'] as Map)['unit'] ?? ''} (${(o['range'] as Map)['source'] ?? 'laboratory'})',
                        )
                      : const Text('No reference range configured'),
                  trailing: _flagLabel(o['flag']).isEmpty
                      ? null
                      : Text(
                          _flagLabel(o['flag']),
                          key: Key('lab-flag-${o['code']}'),
                          style: EcTypography.bodyStrong.copyWith(
                            color: '${o['flag']}'.startsWith('critical')
                                ? EcColors.error
                                : EcColors.warning,
                          ),
                        ),
                ),
            ],
          ],
        );
      },
    );
  }
}
