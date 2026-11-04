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

const _baseMethods = ['cash', 'upi', 'card', 'bank_transfer', 'cheque'];

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

/// Methods the clinic accepts (built-in plus any it configured).
Future<List<String>> paymentMethodsOf(WidgetRef ref) async {
  try {
    final s = await ref
        .read(controlPlaneRepositoryProvider)
        .getMap('/billing/gateway');
    final m = ((s['methods'] as List?) ?? const []).cast<String>();
    return m.isEmpty ? _baseMethods : m;
  } on ApiFailure {
    return _baseMethods;
  }
}

/// Records a payment that staff received for [inv]. The server calculates the
/// balance; the Idempotency-Key makes a repeated tap safe.
Future<void> collectPayment(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> inv,
) async {
  final methods = await paymentMethodsOf(ref);
  if (!context.mounted) return;
  final due = inv['outstanding'] as int? ?? 0;
  final v = await showRecordDialog(
    context,
    title: 'Collect payment',
    note:
        'Record money you have actually received. ${Fmt.money(due, inv['currency'])} is outstanding.',
    confirmLabel: 'Record payment',
    initial: {'amount': minorToInput(due), 'method': 'cash'},
    fields: [
      const FieldSpec(
        'amount',
        'Amount received',
        kind: FieldKind.money,
        required: true,
        maxLength: 12,
      ),
      FieldSpec(
        'method',
        'Method',
        kind: FieldKind.choice,
        options: methods,
        required: true,
      ),
      const FieldSpec(
        'reference',
        'Transaction reference (UPI / card / bank / cheque)',
        maxLength: 100,
      ),
      const FieldSpec(
        'notes',
        'Notes',
        kind: FieldKind.multiline,
        maxLength: 500,
      ),
    ],
  );
  if (v == null || !context.mounted) return;
  final amount = parseMinor('${v['amount']}');
  if (amount == null) return;
  Map<String, Object?>? payment;
  final ok = await runAction(
    context,
    action: () async {
      payment = await ref
          .read(controlPlaneRepositoryProvider)
          .sendMap(
            'POST',
            '/billing/payments',
            {
              'patientId': inv['patientId'],
              'branchId': inv['branchId'],
              'amountMinor': amount,
              'method': v['method'],
              'reference': ?v['reference'],
              'notes': ?v['notes'],
              'allocations': [
                {'invoiceId': inv['invoiceId'], 'amountMinor': amount},
              ],
            },
            {'Idempotency-Key': newIdempotencyKey()},
          );
    },
    success: 'Payment recorded.',
    after: () => _refresh(ref),
  );
  final receipt = payment?['receipt'];
  if (ok && receipt is Map<String, Object?> && context.mounted) {
    context.go('/clinic/billing/receipts/${receipt['receiptId']}');
  }
}

/// Records an advance payment that becomes patient credit.
Future<void> recordAdvance(
  BuildContext context,
  WidgetRef ref, {
  required String patientId,
  required String branchId,
}) async {
  final methods = await paymentMethodsOf(ref);
  if (!context.mounted) return;
  final v = await showRecordDialog(
    context,
    title: 'Record advance',
    note:
        'The amount is kept as credit for this patient and can be applied to invoices later.',
    confirmLabel: 'Record advance',
    initial: const {'method': 'cash'},
    fields: [
      const FieldSpec(
        'amount',
        'Amount received',
        kind: FieldKind.money,
        required: true,
        maxLength: 12,
      ),
      FieldSpec(
        'method',
        'Method',
        kind: FieldKind.choice,
        options: methods,
        required: true,
      ),
      const FieldSpec('reference', 'Transaction reference', maxLength: 100),
    ],
  );
  if (v == null || !context.mounted) return;
  final amount = parseMinor('${v['amount']}');
  if (amount == null) return;
  await runAction(
    context,
    action: () async {
      await ref
          .read(controlPlaneRepositoryProvider)
          .sendMap(
            'POST',
            '/billing/patient-credits',
            {
              'kind': 'advance',
              'patientId': patientId,
              'branchId': branchId,
              'amountMinor': amount,
              'method': v['method'],
              'reference': ?v['reference'],
            },
            {'Idempotency-Key': newIdempotencyKey()},
          );
    },
    success: 'Advance recorded.',
    after: () => _refresh(ref),
  );
}

/// Payments received, newest first.
class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Payments',
      subtitle: 'Money received at the clinic.',
      path: '/billing/payments',
      searchHint: 'Search is by filter below',
      extraDropdown: ('Method', 'method', _baseMethods),
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No payments yet',
      emptyMessage:
          'Payments appear here once collected against an invoice or as an advance.',
      rowBuilder: (context, r) => RowCard(
        title: '${r['receiptNumber']} · ${r['patientName']}',
        subtitle:
            '${Fmt.humanize(r['method'])} · ${Fmt.dateTime(r['receivedAt'])}',
        trailing: Fmt.money(r['amount'], r['currency']),
        status: r['status'],
        onTap: () => context.go('/clinic/billing/payments/${r['paymentId']}'),
      ),
    );
  }
}

/// A payment with its allocations and refunds; the place to ask for a refund.
class PaymentDetailPage extends ConsumerWidget {
  const PaymentDetailPage({required this.paymentId, super.key});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/billing/payments/$paymentId');
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (p) {
        final cur = p['currency'];
        String m(Object? v) => Fmt.money(v, cur);
        final allocations = ((p['allocations'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        final refunds = ((p['refunds'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Payment ${p['receiptNumber']}',
              subtitle: '${p['patientName']} · ${p['patientMrn'] ?? ''}',
              actions: [
                statusChip(p['status']),
                sized(
                  EcSecondaryButton(
                    label: 'View receipt',
                    icon: Icons.receipt_long_outlined,
                    onPressed: () => context.go(
                      '/clinic/billing/receipts/${p['receiptId']}',
                    ),
                  ),
                ),
              ],
            ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Amount', m(p['amount'])),
                ('Method', Fmt.humanize(p['method'])),
                ('Reference', p['reference']),
                ('Received', Fmt.dateTime(p['receivedAt'])),
                ('Received by', '${p['receivedByRole'] ?? ''}'),
                ('Applied to invoices', m(p['allocatedTotal'])),
                if ((p['advanceAmount'] ?? 0) != 0)
                  ('Advance (credit)', m(p['advanceAmount'])),
                ('Refunded', m(p['refundedTotal'])),
                ('Notes', p['notes']),
              ]),
            ),
            Section(
              title: 'Applied to',
              child: allocations.isEmpty
                  ? const Text('Kept entirely as advance credit.')
                  : Column(
                      children: [
                        for (final a in allocations)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${a['invoiceNumber'] ?? a['invoiceId']} · ${m(a['amount'])}',
                            ),
                            trailing: TextButton(
                              onPressed: () => context.go(
                                '/clinic/billing/invoices/${a['invoiceId']}',
                              ),
                              child: const Text('Open'),
                            ),
                          ),
                      ],
                    ),
            ),
            if (refunds.isNotEmpty)
              Section(
                title: 'Refunds',
                child: Column(
                  children: [
                    for (final r in refunds)
                      ListTile(
                        dense: true,
                        title: Text(m(r['amount'])),
                        trailing: statusChip(r['status']),
                        onTap: () => context.go(
                          '/clinic/billing/refunds/${r['refundId']}',
                        ),
                      ),
                  ],
                ),
              ),
            if (can(ref, ClinicPermission.refundRequest))
              sized(
                EcSecondaryButton(
                  label: 'Request refund',
                  icon: Icons.undo,
                  onPressed: () => _requestRefund(context, ref, p, allocations),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _requestRefund(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> p,
    List<Map<String, Object?>> allocations,
  ) async {
    String label(Map<String, Object?> a) =>
        '${a['invoiceNumber'] ?? a['invoiceId']} — ${Fmt.money(a['amount'], p['currency'])}';
    final v = await showRecordDialog(
      context,
      title: 'Request refund',
      note:
          'A refund needs approval, and is recorded only when the money is actually paid back.',
      confirmLabel: 'Request refund',
      fields: [
        if (allocations.isNotEmpty)
          FieldSpec(
            'invoice',
            'Invoice to refund against',
            kind: FieldKind.choice,
            options: [for (final a in allocations) label(a)],
          ),
        const FieldSpec(
          'amount',
          'Amount to refund',
          kind: FieldKind.money,
          required: true,
          maxLength: 12,
        ),
        const FieldSpec('reason', 'Reason', required: true, maxLength: 300),
      ],
    );
    if (v == null || !context.mounted) return;
    final amount = parseMinor('${v['amount']}');
    if (amount == null) return;
    final alloc = allocations.where((a) => label(a) == v['invoice']);
    await runAction(
      context,
      action: () async {
        await ref
            .read(controlPlaneRepositoryProvider)
            .sendMap(
              'POST',
              '/billing/refunds',
              {
                'paymentId': paymentId,
                if (alloc.isNotEmpty) 'invoiceId': alloc.first['invoiceId'],
                'amountMinor': amount,
                'reason': v['reason'],
              },
              {'Idempotency-Key': newIdempotencyKey()},
            );
      },
      success: 'Refund requested.',
      after: () => _refresh(ref),
    );
  }
}

/// A receipt as it would be printed. Opening it again never creates a payment.
class ReceiptPage extends ConsumerWidget {
  const ReceiptPage({required this.receiptId, super.key});

  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/billing/receipts/$receiptId');
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (r) {
        final cur = r['currency'];
        String m(Object? v) => Fmt.money(v, cur);
        final clinic = (r['clinic'] as Map?) ?? const {};
        final address = clinic['address'];
        final invoices = ((r['invoices'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Receipt ${r['receiptNumber']}',
              subtitle:
                  'A copy of this receipt can be opened again at any time.',
              actions: [
                TextButton(
                  onPressed: () =>
                      context.go('/clinic/billing/payments/${r['paymentId']}'),
                  child: const Text('Payment'),
                ),
              ],
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: EcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${clinic['name'] ?? 'Clinic'}',
                        style: EcTypography.sectionTitle,
                      ),
                      if (clinic['branchName'] != null)
                        Text(
                          '${clinic['branchName']}',
                          style: EcTypography.bodySecondary,
                        ),
                      if (address is Map)
                        Text(
                          [
                                address['line1'],
                                address['city'],
                                address['state'],
                                address['postalCode'],
                              ]
                              .where((e) => e != null && '$e'.isNotEmpty)
                              .join(', '),
                          style: EcTypography.bodySecondary,
                        ),
                      if (clinic['phone'] != null)
                        Text(
                          '${clinic['phone']}',
                          style: EcTypography.bodySecondary,
                        ),
                      const Divider(height: EcSpacing.xl),
                      KeyValues([
                        ('Receipt number', r['receiptNumber']),
                        ('Date', Fmt.dateTime(r['receivedAt'])),
                        (
                          'Patient',
                          '${r['patientName']} (${r['patientMrn'] ?? ''})',
                        ),
                        ('Method', Fmt.humanize(r['method'])),
                        ('Reference', r['reference']),
                        ('Received by', r['receivedByRole']),
                      ]),
                      const SizedBox(height: EcSpacing.md),
                      for (final i in invoices)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Invoice ${i['invoiceNumber']}'),
                          subtitle: Text(
                            'Balance after this payment: ${m(i['outstandingAfter'])}',
                          ),
                          trailing: Text(m(i['amount'])),
                        ),
                      if ((r['advanceAmount'] ?? 0) != 0)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Advance kept as credit'),
                          trailing: Text(m(r['advanceAmount'])),
                        ),
                      const Divider(height: EcSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Amount received',
                              style: EcTypography.bodyStrong,
                            ),
                          ),
                          Text(
                            m(r['amount']),
                            key: const Key('receipt-amount'),
                            style: EcTypography.sectionTitle,
                          ),
                        ],
                      ),
                      const SizedBox(height: EcSpacing.sm),
                      Text(
                        'Total outstanding for this patient now: ${m(r['patientOutstandingNow'])}',
                        style: EcTypography.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A patient's money: what is owed, advance credit, and the actions on both.
class PatientBillingPage extends ConsumerWidget {
  const PatientBillingPage({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cq = Query('/billing/patients/$patientId/credits');
    final iq = Query('/billing/invoices', {
      'patientId': patientId,
      'limit': '50',
    });
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Patient account',
          subtitle: 'Invoices, outstanding balance and advance credit.',
        ),
        AsyncBody(
          value: ref.watch(listProvider(iq)),
          onRetry: () => ref.invalidate(listProvider(iq)),
          builder: (invoices) {
            final open = [
              for (final i in invoices)
                if (((i['outstanding'] as int?) ?? 0) > 0 &&
                    i['status'] != 'cancelled' &&
                    i['status'] != 'draft')
                  i,
            ];
            final total = open.fold<int>(
              0,
              (a, i) => a + (i['outstanding'] as int),
            );
            final branchId = invoices.isEmpty
                ? null
                : '${invoices.first['branchId']}';
            return Section(
              title: 'Outstanding',
              trailing: can(ref, ClinicPermission.billingCreate)
                  ? sized(
                      EcSecondaryButton(
                        label: 'New invoice',
                        icon: Icons.add,
                        onPressed: () =>
                            context.go('/clinic/billing/invoices/new'),
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.money(
                      total,
                      invoices.isEmpty ? null : invoices.first['currency'],
                    ),
                    key: const Key('patient-outstanding'),
                    style: EcTypography.sectionTitle,
                  ),
                  if (open.isEmpty) const Text('Nothing is owed.'),
                  for (final i in open)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${i['invoiceNumber']} · due ${i['dueDate']}',
                      ),
                      trailing: Text(
                        Fmt.money(i['outstanding'], i['currency']),
                      ),
                      onTap: () => context.go(
                        '/clinic/billing/invoices/${i['invoiceId']}',
                      ),
                    ),
                  if (branchId == null) const SizedBox.shrink(),
                ],
              ),
            );
          },
        ),
        AsyncBody(
          value: ref.watch(mapProvider(cq)),
          onRetry: () => ref.invalidate(mapProvider(cq)),
          builder: (c) {
            final cur = c['currency'];
            final sources = ((c['sources'] as List?) ?? const [])
                .cast<Map<String, Object?>>();
            final ledger = ((c['ledger'] as List?) ?? const [])
                .cast<Map<String, Object?>>();
            return Section(
              title: 'Advance credit',
              trailing: can(ref, ClinicPermission.paymentRecordAdvance)
                  ? sized(
                      EcSecondaryButton(
                        label: 'Record advance',
                        icon: Icons.add_card,
                        onPressed: () async {
                          final b =
                              ref.read(activeBranchProvider) ??
                              await _firstBranch(ref);
                          if (b != null && context.mounted) {
                            await recordAdvance(
                              context,
                              ref,
                              patientId: patientId,
                              branchId: b,
                            );
                          }
                        },
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.money(c['balance'], cur),
                    key: const Key('credit-balance'),
                    style: EcTypography.sectionTitle,
                  ),
                  Text('Available credit', style: EcTypography.bodySecondary),
                  if (sources.isNotEmpty &&
                      can(ref, ClinicPermission.paymentAllocate))
                    Padding(
                      padding: const EdgeInsets.only(top: EcSpacing.sm),
                      child: sized(
                        EcSecondaryButton(
                          label: 'Apply credit to an invoice',
                          onPressed: () =>
                              _applyCredit(context, ref, sources, cur),
                        ),
                      ),
                    ),
                  const SizedBox(height: EcSpacing.md),
                  if (ledger.isEmpty) const Text('No credit history.'),
                  for (final e in ledger.take(20))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${Fmt.humanize(e['type'])} · ${Fmt.money(e['amount'], cur)}',
                      ),
                      subtitle: Text(
                        '${Fmt.dateTime(e['createdAt'])} · balance ${Fmt.money(e['balanceAfter'], cur)}',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<String?> _firstBranch(WidgetRef ref) async {
    final b = await ref.read(controlPlaneRepositoryProvider).getList(
      '/branches',
      {'limit': '5'},
    );
    return b.isEmpty ? null : '${b.first['branchId']}';
  }

  Future<void> _applyCredit(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, Object?>> sources,
    Object? cur,
  ) async {
    final invoices = await ref.read(controlPlaneRepositoryProvider).getList(
      '/billing/invoices',
      {'patientId': patientId, 'limit': '50'},
    );
    final open = [
      for (final i in invoices)
        if (((i['outstanding'] as int?) ?? 0) > 0 &&
            i['status'] != 'cancelled' &&
            i['status'] != 'draft')
          i,
    ];
    if (!context.mounted) return;
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invoice has an outstanding balance.')),
      );
      return;
    }
    String il(Map<String, Object?> i) =>
        '${i['invoiceNumber']} — ${Fmt.money(i['outstanding'], cur)} due';
    final v = await showRecordDialog(
      context,
      title: 'Apply credit',
      note:
          'The credit is applied oldest first; the server limits the amount to what is left.',
      confirmLabel: 'Apply credit',
      fields: [
        FieldSpec(
          'invoice',
          'Invoice',
          kind: FieldKind.choice,
          options: [for (final i in open) il(i)],
          required: true,
        ),
        const FieldSpec(
          'amount',
          'Amount',
          kind: FieldKind.money,
          required: true,
          maxLength: 12,
        ),
      ],
    );
    if (v == null || !context.mounted) return;
    final amount = parseMinor('${v['amount']}');
    if (amount == null) return;
    final inv = open.firstWhere((i) => il(i) == v['invoice']);
    await runAction(
      context,
      action: () async {
        await ref
            .read(controlPlaneRepositoryProvider)
            .sendMap(
              'POST',
              '/billing/patient-credits/${sources.first['entryId']}/allocations',
              {
                'allocations': [
                  {'invoiceId': inv['invoiceId'], 'amountMinor': amount},
                ],
              },
              {'Idempotency-Key': newIdempotencyKey()},
            );
      },
      success: 'Credit applied.',
      after: () => _refresh(ref),
    );
  }
}
