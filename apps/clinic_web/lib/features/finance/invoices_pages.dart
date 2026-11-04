import 'package:app_core/app_core.dart';
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
import 'payments_pages.dart';

const invoiceFilterStatuses = [
  'draft',
  'finalized',
  'partially_paid',
  'paid',
  'overdue',
  'cancelled',
  'partially_refunded',
  'refunded',
];

/// Invoice list with search by number and status filter.
class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Invoices',
      subtitle:
          'Bills raised for patients. Amounts are calculated by the server.',
      path: '/billing/invoices',
      searchHint: 'Invoice number (INV-000001)',
      statusOptions: invoiceFilterStatuses,
      emptyTitle: 'No invoices',
      emptyMessage: 'Create an invoice to start billing.',
      extraParams: {'branchId': ?branch},
      actions: [
        if (can(ref, ClinicPermission.billingCreate))
          sized(
            EcPrimaryButton(
              label: 'New invoice',
              icon: Icons.add,
              onPressed: () => context.go('/clinic/billing/invoices/new'),
            ),
          ),
      ],
      rowBuilder: (context, r) => RowCard(
        title: '${r['invoiceNumber'] ?? 'Draft'} · ${r['patientName']}',
        subtitle:
            '${r['patientMrn'] ?? ''} · ${Fmt.date(r['invoiceDate'])}'
            ' · due ${r['dueDate'] ?? '—'}',
        trailing: r['status'] == 'draft'
            ? Fmt.money(r['grandTotal'], r['currency'])
            : 'Due ${Fmt.money(r['outstanding'], r['currency'])}',
        status: r['displayStatus'] ?? r['status'],
        onTap: () => context.go('/clinic/billing/invoices/${r['invoiceId']}'),
      ),
    );
  }
}

/// Starts a draft invoice for a patient (optionally from an appointment).
class NewInvoicePage extends ConsumerStatefulWidget {
  const NewInvoicePage({this.initial = const {}, super.key});

  final Map<String, String> initial;

  @override
  ConsumerState<NewInvoicePage> createState() => _NewInvoiceState();
}

class _NewInvoiceState extends ConsumerState<NewInvoicePage> {
  Map<String, Object?>? _patient;
  String? _branch;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pid = widget.initial['patientId'];
    if (pid != null) {
      _patient = {
        'patientId': pid,
        'fullName': widget.initial['patientName'] ?? 'Patient',
        'mrn': widget.initial['patientMrn'],
        'branchId': widget.initial['branchId'],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const <Json>[];
    final active = ref.watch(activeBranchProvider);
    final branch =
        _branch ??
        widget.initial['branchId'] ??
        (_patient?['branchId'] as String?) ??
        active ??
        (branches.length == 1 ? '${branches.single['branchId']}' : null);
    final appointmentId = widget.initial['appointmentId'];
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'New invoice',
          subtitle: 'Choose the patient, then add services on the next screen.',
        ),
        Section(
          title: 'Patient',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_patient != null)
                Text(
                  '${_patient!['fullName']} · ${_patient!['mrn'] ?? ''}',
                  style: EcTypography.bodyStrong,
                ),
              const SizedBox(height: EcSpacing.sm),
              sized(
                EcSecondaryButton(
                  label: _patient == null ? 'Find patient' : 'Change patient',
                  icon: Icons.person_search_outlined,
                  onPressed: () async {
                    final p = await pickPatient(context);
                    if (p != null) setState(() => _patient = p);
                  },
                ),
              ),
            ],
          ),
        ),
        if (branches.length > 1)
          Section(
            title: 'Branch',
            child: SizedBox(
              width: 320,
              child: EcDropdown<String>(
                label: 'Branch',
                items: [for (final b in branches) '${b['branchId']}'],
                value: branch,
                itemLabel: (id) =>
                    '${branches.firstWhere((b) => b['branchId'] == id)['name']}',
                onChanged: (v) => setState(() => _branch = v),
              ),
            ),
          ),
        if (appointmentId != null)
          const EcInlineMessage(
            tone: EcStatusTone.info,
            message:
                'This invoice will be linked to the appointment you came from.',
          ),
        if (_error != null)
          EcInlineMessage(tone: EcStatusTone.error, message: _error!),
        const SizedBox(height: EcSpacing.md),
        sized(
          EcPrimaryButton(
            label: 'Create draft',
            onPressed: _patient == null || branch == null || _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      final inv = await ref
                          .read(controlPlaneRepositoryProvider)
                          .sendMap('POST', '/billing/invoices', {
                            'patientId': _patient!['patientId'],
                            'branchId': branch,
                            'appointmentId': ?appointmentId,
                          });
                      if (context.mounted) {
                        context.go(
                          '/clinic/billing/invoices/${inv['invoiceId']}',
                        );
                      }
                    } on ApiFailure catch (e) {
                      if (mounted) setState(() => _error = failureText(e));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
          220,
        ),
      ],
    );
  }
}

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

/// One invoice: lines, totals, payments, adjustments and the actions its
/// status allows.
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  Map<String, Object?> _input(Map<String, Object?> l) => {
    if (l['serviceId'] != null) ...{
      'serviceId': l['serviceId'],
      'description': l['description'],
    } else ...{
      'description': l['description'],
      'unitMinor': l['unitMinor'],
      'category': l['category'],
      if (l['taxRuleId'] != null) 'taxRuleId': l['taxRuleId'],
    },
    'quantity': l['quantity'],
    if (l['discountType'] != null)
      'discount': {'type': l['discountType'], 'value': l['discountValue']},
    if (l['taxExempt'] == true) ...{
      'taxExempt': true,
      'taxExemptReason': l['taxExemptReason'],
    },
  };

  Future<void> _setLines(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> inv,
    List<Map<String, Object?>> lines,
  ) => runAction(
    context,
    action: () => ref.read(controlPlaneRepositoryProvider).sendMap(
      'PATCH',
      '/billing/invoices/$invoiceId',
      {'lines': lines, 'expectedRev': inv['rev']},
    ),
    success: 'Invoice updated.',
    after: () => _refresh(ref),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/billing/invoices/$invoiceId');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (inv) {
        final status = '${inv['status']}';
        final cur = inv['currency'];
        String m(Object? v) => Fmt.money(v, cur);
        final draft = status == 'draft';
        final lines = ((inv['lines'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final allocations = ((inv['allocations'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final adjustments = ((inv['adjustments'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final outstanding = (inv['outstanding'] as int?) ?? 0;
        final canPay =
            const {
              'finalized',
              'partially_paid',
              'partially_refunded',
              'paid',
              'refunded',
            }.contains(status) &&
            outstanding > 0;
        final canAdjust = !draft && status != 'cancelled';
        final unpaid = ((inv['amountPaid'] as int?) ?? 0) == 0;
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: inv['invoiceNumber'] != null
                  ? 'Invoice ${inv['invoiceNumber']}'
                  : 'Draft invoice',
              subtitle:
                  '${inv['patientName']} · ${inv['patientMrn'] ?? ''} · '
                  '${inv['branchName'] ?? ''}',
              actions: [
                statusChip(inv['displayStatus'] ?? status),
                TextButton(
                  onPressed: () => context.go(
                    '/clinic/billing/patients/${inv['patientId']}',
                  ),
                  child: const Text('Patient account'),
                ),
              ],
            ),
            if (inv['overdue'] == true)
              EcInlineMessage(
                tone: EcStatusTone.warning,
                message:
                    'Overdue since ${inv['dueDate']}. ${m(outstanding)} is outstanding.',
              ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Invoice date', inv['invoiceDate']),
                ('Due date', inv['dueDate']),
                ('Currency', cur),
                (
                  'Finalized',
                  inv['finalizedAt'] == null
                      ? null
                      : Fmt.dateTime(inv['finalizedAt']),
                ),
                ('Cancelled', inv['cancelReason']),
                ('Notes', inv['notes']),
              ]),
            ),
            Section(
              title: 'Lines',
              trailing: draft && can(ref, ClinicPermission.billingEditDraft)
                  ? Wrap(
                      spacing: EcSpacing.sm,
                      children: [
                        sized(
                          EcSecondaryButton(
                            label: 'Add service',
                            icon: Icons.add,
                            onPressed: () =>
                                _addService(context, ref, inv, lines),
                          ),
                        ),
                        sized(
                          EcSecondaryButton(
                            label: 'Custom item',
                            icon: Icons.edit_note,
                            onPressed: () =>
                                _addCustom(context, ref, inv, lines),
                          ),
                        ),
                      ],
                    )
                  : null,
              child: lines.isEmpty
                  ? const Text(
                      'No lines yet. Add a service from the catalogue.',
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < lines.length; i++)
                          ListTile(
                            key: Key('line-$i'),
                            dense: true,
                            title: Text('${lines[i]['description']}'),
                            subtitle: Text(
                              '${lines[i]['quantity']} × ${m(lines[i]['unitMinor'])}'
                              '${lines[i]['lineDiscount'] != 0 ? ' · discount ${m(lines[i]['lineDiscount'])}' : ''}'
                              '${(lines[i]['tax'] as int? ?? 0) > 0 ? ' · tax ${m(lines[i]['tax'])} (${lines[i]['taxRuleName']})' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  m(lines[i]['total']),
                                  style: EcTypography.bodyStrong,
                                ),
                                if (draft &&
                                    can(ref, ClinicPermission.billingEditDraft))
                                  IconButton(
                                    tooltip: 'Remove line',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        _setLines(context, ref, inv, [
                                          for (var j = 0; j < lines.length; j++)
                                            if (j != i) _input(lines[j]),
                                        ]),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Totals',
              trailing: draft && can(ref, ClinicPermission.billingApplyDiscount)
                  ? sized(
                      EcSecondaryButton(
                        label: 'Discount',
                        icon: Icons.percent,
                        onPressed: () => _discount(context, ref, inv),
                      ),
                    )
                  : null,
              child: KeyValues([
                ('Subtotal', m(inv['subtotal'])),
                (
                  'Discounts',
                  m(
                    inv['discountTotal'] ??
                        ((inv['lineDiscountTotal'] as int? ?? 0) +
                            (inv['invoiceDiscount'] as int? ?? 0)),
                  ),
                ),
                ('Tax', m(inv['taxTotal'])),
                ('Grand total', m(inv['grandTotal'])),
                if ((inv['adjustmentDebits'] ?? 0) != 0)
                  ('Debit notes', m(inv['adjustmentDebits'])),
                if ((inv['adjustmentCredits'] ?? 0) != 0)
                  ('Credit notes', m(inv['adjustmentCredits'])),
                if (!draft) ('Paid', m(inv['amountPaid'])),
                if ((inv['amountRefunded'] ?? 0) != 0)
                  ('Refunded', m(inv['amountRefunded'])),
                if (!draft) ('Outstanding', m(inv['outstanding'])),
              ]),
            ),
            if (allocations.isNotEmpty)
              Section(
                title: 'Payments',
                child: Column(
                  children: [
                    for (final a in allocations)
                      ListTile(
                        dense: true,
                        title: Text(m(a['amount'])),
                        subtitle: Text(
                          '${a['source'] == 'credit' ? 'From advance credit' : 'Payment'} · ${Fmt.dateTime(a['createdAt'])}',
                        ),
                        trailing: a['paymentId'] == null
                            ? null
                            : TextButton(
                                onPressed: () => context.go(
                                  '/clinic/billing/payments/${a['paymentId']}',
                                ),
                                child: const Text('Open'),
                              ),
                      ),
                  ],
                ),
              ),
            if (adjustments.isNotEmpty)
              Section(
                title: 'Adjustments',
                child: Column(
                  children: [
                    for (final a in adjustments)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${a['number']} · ${a['type'] == 'credit' ? 'Credit note' : 'Debit note'} · ${m(a['amount'])}',
                        ),
                        subtitle: Text('${a['reason']}'),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                if (draft && can(ref, ClinicPermission.billingFinalize))
                  sized(
                    EcPrimaryButton(
                      label: 'Finalize invoice',
                      icon: Icons.lock_outline,
                      onPressed: lines.isEmpty
                          ? null
                          : () async {
                              final sure = await _confirm(
                                context,
                                'Finalize invoice?',
                                'The prices and tax are fixed. Later changes need a credit or debit note.',
                                'Finalize',
                              );
                              if (sure && context.mounted) {
                                await runAction(
                                  context,
                                  action: () => repo.sendMap(
                                    'POST',
                                    '/billing/invoices/$invoiceId/finalize',
                                  ),
                                  success: 'Invoice finalized.',
                                  after: () => _refresh(ref),
                                );
                              }
                            },
                    ),
                  ),
                if (canPay && can(ref, ClinicPermission.paymentCollect))
                  sized(
                    EcPrimaryButton(
                      label: 'Collect payment',
                      icon: Icons.payments_outlined,
                      onPressed: () => collectPayment(context, ref, inv),
                    ),
                  ),
                if (canAdjust && can(ref, ClinicPermission.billingAdjust))
                  sized(
                    EcSecondaryButton(
                      label: 'Credit / debit note',
                      icon: Icons.tune,
                      onPressed: () => _adjust(context, ref),
                    ),
                  ),
                if (status != 'cancelled' &&
                    unpaid &&
                    can(ref, ClinicPermission.billingCancel))
                  sized(
                    EcSecondaryButton(
                      label: 'Cancel invoice',
                      icon: Icons.cancel_outlined,
                      onPressed: () async {
                        final reason = await askReason(
                          context,
                          title: 'Cancel invoice',
                          message:
                              'A cancelled invoice stays on record with your reason.',
                          confirmLabel: 'Cancel invoice',
                        );
                        if (reason != null && context.mounted) {
                          await runAction(
                            context,
                            action: () => repo.sendMap(
                              'POST',
                              '/billing/invoices/$invoiceId/cancel',
                              {'reason': reason},
                            ),
                            success: 'Invoice cancelled.',
                            after: () => _refresh(ref),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
    String label,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addService(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> inv,
    List<Map<String, Object?>> lines,
  ) async {
    final services = await ref.read(controlPlaneRepositoryProvider).getList(
      '/billing/services',
      {'status': 'active', 'limit': '100'},
    );
    if (!context.mounted) return;
    if (services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The service catalogue is empty. Add services first, or use a custom item.',
          ),
        ),
      );
      return;
    }
    String label(Map<String, Object?> s) =>
        '${s['name']} — ${Fmt.money(s['amountMinor'], s['currency'])}';
    final v = await showRecordDialog(
      context,
      title: 'Add service',
      note: 'The server applies the current catalogue price and tax.',
      fields: [
        FieldSpec(
          'service',
          'Service',
          kind: FieldKind.choice,
          options: [for (final s in services) label(s)],
          required: true,
        ),
        const FieldSpec('quantity', 'Quantity', required: true, maxLength: 4),
      ],
      initial: const {'quantity': '1'},
    );
    if (v == null || !context.mounted) return;
    final s = services.firstWhere((s) => label(s) == v['service']);
    final qty = int.tryParse('${v['quantity']}');
    if (qty == null || qty < 1) return;
    await _setLines(context, ref, inv, [
      for (final l in lines) _input(l),
      {'serviceId': s['serviceId'], 'quantity': qty},
    ]);
  }

  Future<void> _addCustom(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> inv,
    List<Map<String, Object?>> lines,
  ) async {
    final v = await showRecordDialog(
      context,
      title: 'Custom item',
      note: 'For a one-off charge that is not in the catalogue.',
      fields: const [
        FieldSpec('description', 'Description', required: true),
        FieldSpec(
          'amount',
          'Unit price',
          kind: FieldKind.money,
          required: true,
          maxLength: 12,
        ),
        FieldSpec('quantity', 'Quantity', required: true, maxLength: 4),
      ],
      initial: const {'quantity': '1'},
    );
    if (v == null || !context.mounted) return;
    final unit = parseMinor('${v['amount']}');
    final qty = int.tryParse('${v['quantity']}');
    if (unit == null || qty == null || qty < 1) return;
    await _setLines(context, ref, inv, [
      for (final l in lines) _input(l),
      {
        'description': v['description'],
        'unitMinor': unit,
        'quantity': qty,
        'category': 'custom',
      },
    ]);
  }

  Future<void> _discount(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> inv,
  ) async {
    final v = await showRecordDialog(
      context,
      title: 'Invoice discount',
      note:
          'Your role has a discount limit set by the clinic. Leave the value empty to remove the discount.',
      fields: const [
        FieldSpec(
          'type',
          'Type',
          kind: FieldKind.choice,
          options: ['percent', 'fixed'],
        ),
        FieldSpec(
          'value',
          'Value (percent, or rupees for fixed)',
          maxLength: 12,
        ),
      ],
    );
    if (v == null || !context.mounted) return;
    Object? discount;
    if (v['type'] != null && v['value'] != null) {
      final value = v['type'] == 'percent'
          ? parseBps('${v['value']}')
          : parseMinor('${v['value']}');
      if (value == null) return;
      discount = {'type': v['type'], 'value': value};
    }
    await runAction(
      context,
      action: () => ref.read(controlPlaneRepositoryProvider).sendMap(
        'PATCH',
        '/billing/invoices/$invoiceId',
        {'discount': discount, 'expectedRev': inv['rev']},
      ),
      success: 'Discount applied.',
      after: () => _refresh(ref),
    );
  }

  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final v = await showRecordDialog(
      context,
      title: 'Credit or debit note',
      note:
          'A credit note reduces what is owed (never below zero). Money already paid is returned through a refund.',
      fields: const [
        FieldSpec(
          'type',
          'Type',
          kind: FieldKind.choice,
          options: ['credit', 'debit'],
          required: true,
        ),
        FieldSpec(
          'amount',
          'Amount',
          kind: FieldKind.money,
          required: true,
          maxLength: 12,
        ),
        FieldSpec('reason', 'Reason', required: true, maxLength: 300),
      ],
    );
    if (v == null || !context.mounted) return;
    final amount = parseMinor('${v['amount']}');
    if (amount == null) return;
    await runAction(
      context,
      action: () => ref.read(controlPlaneRepositoryProvider).sendMap(
        'POST',
        '/billing/invoices/$invoiceId/adjustments',
        {'type': v['type'], 'amountMinor': amount, 'reason': v['reason']},
      ),
      success: 'Note recorded.',
      after: () => _refresh(ref),
    );
  }
}
