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
import 'payments_pages.dart' show paymentMethodsOf;

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

// ------------------------------------------------------------------ refunds

class RefundsPage extends ConsumerWidget {
  const RefundsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Refunds',
      subtitle:
          'Requests, approvals and payouts. A refund never edits the original payment.',
      path: '/billing/refunds',
      statusOptions: const [
        'requested',
        'approved',
        'rejected',
        'processing',
        'completed',
        'failed',
      ],
      searchHint: 'Filter by status',
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No refunds',
      emptyMessage: 'Refunds are requested from a payment.',
      rowBuilder: (context, r) => RowCard(
        title: '${r['patientName']} · ${Fmt.money(r['amount'], r['currency'])}',
        subtitle:
            '${r['invoiceNumber'] ?? 'Advance'} · ${Fmt.dateTime(r['requestedAt'])} · ${r['reason']}',
        status: r['status'],
        onTap: () => context.go('/clinic/billing/refunds/${r['refundId']}'),
      ),
    );
  }
}

class RefundDetailPage extends ConsumerWidget {
  const RefundDetailPage({required this.refundId, super.key});

  final String refundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/billing/refunds/$refundId');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (r) {
        final status = '${r['status']}';
        final history = ((r['history'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        Future<void> act(String action, Map<String, Object?> body, String ok) =>
            runAction(
              context,
              action: () async => repo.sendMap(
                'POST',
                '/billing/refunds/$refundId/$action',
                body,
              ),
              success: ok,
              after: () => _refresh(ref),
            );
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Refund ${Fmt.money(r['amount'], r['currency'])}',
              subtitle:
                  '${r['patientName']} · ${r['invoiceNumber'] ?? 'advance credit'}',
              actions: [
                statusChip(status),
                TextButton(
                  onPressed: () =>
                      context.go('/clinic/billing/payments/${r['paymentId']}'),
                  child: const Text('Original payment'),
                ),
              ],
            ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Reason', r['reason']),
                ('Requested', Fmt.dateTime(r['requestedAt'])),
                (
                  'Approved',
                  r['approvedAt'] == null
                      ? null
                      : Fmt.dateTime(r['approvedAt']),
                ),
                (
                  'Paid back by',
                  r['method'] == null ? null : Fmt.humanize(r['method']),
                ),
                ('Reference', r['reference']),
                ('Attempts', r['attempts']),
                ('Failure', r['failureReason']),
                ('Rejected', r['rejectReason']),
              ]),
            ),
            Section(
              title: 'History',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['status'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['role']}${h['note'] == null ? '' : ' · ${h['note']}'}',
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                if (status == 'requested' &&
                    can(ref, ClinicPermission.refundApprove))
                  sized(
                    EcPrimaryButton(
                      label: 'Approve',
                      onPressed: () => act('approve', {}, 'Refund approved.'),
                    ),
                  ),
                if (const {
                      'requested',
                      'approved',
                      'failed',
                    }.contains(status) &&
                    can(ref, ClinicPermission.refundApprove))
                  sized(
                    EcSecondaryButton(
                      label: status == 'failed' ? 'Abandon refund' : 'Reject',
                      onPressed: () async {
                        final reason = await askReason(
                          context,
                          title: 'Reject refund',
                          message: 'The patient\'s payment stays as it is.',
                          confirmLabel: 'Reject',
                        );
                        if (reason != null && context.mounted) {
                          await act('reject', {
                            'reason': reason,
                          }, 'Refund rejected.');
                        }
                      },
                    ),
                  ),
                if (const {
                      'approved',
                      'processing',
                      'failed',
                    }.contains(status) &&
                    can(ref, ClinicPermission.refundProcess))
                  sized(
                    EcPrimaryButton(
                      label: status == 'failed'
                          ? 'Retry payout'
                          : 'Record payout',
                      onPressed: () async {
                        final methods = await paymentMethodsOf(ref);
                        if (!context.mounted) return;
                        final v = await showRecordDialog(
                          context,
                          title: 'Record payout',
                          note: 'Record how the money was actually paid back.',
                          confirmLabel: 'Save',
                          initial: const {
                            'outcome': 'completed',
                            'method': 'cash',
                          },
                          fields: [
                            const FieldSpec(
                              'outcome',
                              'Outcome',
                              kind: FieldKind.choice,
                              options: ['completed', 'processing', 'failed'],
                              required: true,
                            ),
                            FieldSpec(
                              'method',
                              'Method',
                              kind: FieldKind.choice,
                              options: methods,
                            ),
                            const FieldSpec(
                              'reference',
                              'Transaction reference',
                              maxLength: 100,
                            ),
                            const FieldSpec(
                              'failureReason',
                              'Failure reason (if failed)',
                              maxLength: 300,
                            ),
                          ],
                        );
                        if (v == null || !context.mounted) return;
                        await act('complete', v, 'Refund updated.');
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
}

// ----------------------------------------------------------------- expenses

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Expenses',
      subtitle: 'Clinic and branch spending with approval.',
      path: '/expenses',
      statusOptions: const [
        'draft',
        'submitted',
        'approved',
        'rejected',
        'paid',
      ],
      searchHint: 'Filter by status',
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No expenses',
      emptyMessage: 'Add an expense to track clinic spending.',
      actions: [
        if (can(ref, ClinicPermission.expenseCreate))
          sized(
            EcPrimaryButton(
              label: 'New expense',
              icon: Icons.add,
              onPressed: () => _editExpense(context, ref),
            ),
          ),
        if (can(ref, ClinicPermission.billingSettingsManage))
          sized(
            EcSecondaryButton(
              label: 'Categories',
              onPressed: () => context.go('/clinic/expenses/categories'),
            ),
          ),
      ],
      rowBuilder: (context, r) => RowCard(
        title: '${r['description']}',
        subtitle:
            '${r['categoryName']} · ${r['expenseDate']} · ${r['vendor'] ?? 'no vendor'}',
        trailing: Fmt.money(r['amount'], r['currency']),
        status: r['status'],
        onTap: () => context.go('/clinic/expenses/${r['expenseId']}'),
      ),
    );
  }
}

Future<void> _editExpense(
  BuildContext context,
  WidgetRef ref, {
  Map<String, Object?>? existing,
}) async {
  final repo = ref.read(controlPlaneRepositoryProvider);
  final cats = await repo.getList('/expenses/categories');
  final active = cats.where((c) => c['status'] == 'active').toList();
  if (!context.mounted) return;
  if (active.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add an expense category first.')),
    );
    return;
  }
  final methods = await paymentMethodsOf(ref);
  if (!context.mounted) return;
  String? catName(Object? id) {
    for (final c in active) {
      if (c['categoryId'] == id) return '${c['name']}';
    }
    return null;
  }

  final v = await showRecordDialog(
    context,
    title: existing == null ? 'New expense' : 'Edit expense',
    confirmLabel: 'Save',
    initial: {
      if (existing != null) ...{
        'category': catName(existing['categoryId']),
        'description': existing['description'],
        'amount': minorToInput(existing['amount']),
        'expenseDate': existing['expenseDate'],
        'vendor': existing['vendor'],
        'method': existing['method'],
        'receiptReference': existing['receiptReference'],
      },
    },
    fields: [
      FieldSpec(
        'category',
        'Category',
        kind: FieldKind.choice,
        options: [for (final c in active) '${c['name']}'],
        required: true,
      ),
      const FieldSpec(
        'description',
        'Description',
        required: true,
        maxLength: 300,
      ),
      const FieldSpec(
        'amount',
        'Amount',
        kind: FieldKind.money,
        required: true,
        maxLength: 12,
      ),
      const FieldSpec(
        'expenseDate',
        'Date',
        kind: FieldKind.date,
        required: true,
      ),
      const FieldSpec('vendor', 'Vendor / payee', maxLength: 120),
      FieldSpec(
        'method',
        'Payment method',
        kind: FieldKind.choice,
        options: methods,
      ),
      const FieldSpec(
        'receiptReference',
        'Receipt / bill reference',
        maxLength: 100,
      ),
    ],
  );
  if (v == null || !context.mounted) return;
  final amount = parseMinor('${v['amount']}');
  if (amount == null) return;
  final cat = active.firstWhere((c) => c['name'] == v['category']);
  final branch = ref.read(activeBranchProvider);
  final body = <String, Object?>{
    'categoryId': cat['categoryId'],
    'description': v['description'],
    'amountMinor': amount,
    'expenseDate': v['expenseDate'],
    'vendor': ?v['vendor'],
    'method': ?v['method'],
    'receiptReference': ?v['receiptReference'],
    if (existing == null) 'branchId': ?branch,
    if (existing != null) 'expectedRev': existing['rev'],
  };
  await runAction(
    context,
    action: () async => repo.sendMap(
      existing == null ? 'POST' : 'PATCH',
      existing == null ? '/expenses' : '/expenses/${existing['expenseId']}',
      body,
    ),
    success: existing == null
        ? 'Expense saved as a draft.'
        : 'Expense updated.',
    after: () => _refresh(ref),
  );
}

class ExpenseDetailPage extends ConsumerWidget {
  const ExpenseDetailPage({required this.expenseId, super.key});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/expenses/$expenseId');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (e) {
        final status = '${e['status']}';
        final history = ((e['history'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        Future<void> act(
          String action,
          String ok, [
          Map<String, Object?> body = const {},
        ]) => runAction(
          context,
          action: () async =>
              repo.sendMap('POST', '/expenses/$expenseId/$action', body),
          success: ok,
          after: () => _refresh(ref),
        );
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${e['description']}',
              subtitle:
                  '${e['categoryName']} · ${Fmt.money(e['amount'], e['currency'])}',
              actions: [statusChip(status)],
            ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Date', e['expenseDate']),
                ('Vendor / payee', e['vendor']),
                ('Branch', e['branchId'] ?? 'Clinic-wide'),
                (
                  'Method',
                  e['method'] == null ? null : Fmt.humanize(e['method']),
                ),
                ('Receipt reference', e['receiptReference']),
                ('Rejected', e['rejectReason']),
                (
                  'Paid',
                  e['paidAt'] == null
                      ? null
                      : '${Fmt.dateTime(e['paidAt'])} by ${Fmt.humanize(e['paidMethod'])}',
                ),
              ]),
            ),
            Section(
              title: 'History',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['status'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['role']}${h['note'] == null ? '' : ' · ${h['note']}'}',
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                if ((status == 'draft' || status == 'rejected') &&
                    can(ref, ClinicPermission.expenseEdit))
                  sized(
                    EcSecondaryButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      onPressed: () => _editExpense(context, ref, existing: e),
                    ),
                  ),
                if (status == 'draft' &&
                    can(ref, ClinicPermission.expenseCreate))
                  sized(
                    EcPrimaryButton(
                      label: 'Submit for approval',
                      onPressed: () => act('submit', 'Expense submitted.'),
                    ),
                  ),
                if (status == 'submitted' &&
                    can(ref, ClinicPermission.expenseApprove))
                  sized(
                    EcPrimaryButton(
                      label: 'Approve',
                      onPressed: () => act('approve', 'Expense approved.'),
                    ),
                  ),
                if (status == 'submitted' &&
                    can(ref, ClinicPermission.expenseReject))
                  sized(
                    EcSecondaryButton(
                      label: 'Reject',
                      onPressed: () async {
                        final reason = await askReason(
                          context,
                          title: 'Reject expense',
                          message: 'The submitter will see your reason.',
                          confirmLabel: 'Reject',
                        );
                        if (reason != null && context.mounted) {
                          await act('reject', 'Expense rejected.', {
                            'reason': reason,
                          });
                        }
                      },
                    ),
                  ),
                if (status == 'approved' &&
                    can(ref, ClinicPermission.expensePay))
                  sized(
                    EcPrimaryButton(
                      label: 'Record payment',
                      onPressed: () async {
                        final methods = await paymentMethodsOf(ref);
                        if (!context.mounted) return;
                        final v = await showRecordDialog(
                          context,
                          title: 'Record payment',
                          confirmLabel: 'Record',
                          initial: const {'method': 'cash'},
                          fields: [
                            FieldSpec(
                              'method',
                              'Method',
                              kind: FieldKind.choice,
                              options: methods,
                              required: true,
                            ),
                            const FieldSpec(
                              'reference',
                              'Transaction reference',
                              maxLength: 100,
                            ),
                          ],
                        );
                        if (v != null && context.mounted) {
                          await act('pay', 'Payment recorded.', v);
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
}

class ExpenseCategoriesPage extends ConsumerWidget {
  const ExpenseCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/expenses/categories');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Expense categories',
          subtitle:
              'Rent, supplies, utilities and so on, as your clinic names them.',
          actions: [
            if (can(ref, ClinicPermission.billingSettingsManage))
              sized(
                EcPrimaryButton(
                  label: 'Add category',
                  icon: Icons.add,
                  onPressed: () async {
                    final v = await showRecordDialog(
                      context,
                      title: 'Add category',
                      fields: const [
                        FieldSpec(
                          'name',
                          'Name',
                          required: true,
                          maxLength: 60,
                        ),
                      ],
                    );
                    if (v != null && context.mounted) {
                      await runAction(
                        context,
                        action: () async =>
                            repo.sendMap('POST', '/expenses/categories', v),
                        success: 'Category added.',
                        after: () => _refresh(ref),
                      );
                    }
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
                  title: 'No categories',
                  message: 'Add the categories your clinic uses.',
                )
              : Column(
                  children: [
                    for (final c in rows)
                      ListTile(
                        title: Text('${c['name']}'),
                        trailing: statusChip(c['status']),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
