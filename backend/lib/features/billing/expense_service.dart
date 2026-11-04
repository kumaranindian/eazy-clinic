import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/time_support.dart';
import 'billing_support.dart';

const List<String> expenseStatuses = [
  'draft',
  'submitted',
  'approved',
  'rejected',
  'paid',
];

/// Clinic and branch expenses with an approval workflow. Approved and paid
/// expenses are immutable. Payroll is out of scope.
class ExpenseService {
  ExpenseService(this._s);

  final BillingSupport _s;

  static const String collection = 'expenses';

  // --------------------------------------------------------- categories

  Future<List<Map<String, Object?>>> categories(TenantContext t) async {
    t.require(ClinicPermission.expenseView);
    final rows = await _s.d.store.query(
      DocQuery(_s.path(t, 'expense_categories'), limit: 200),
    );
    return [for (final r in rows) BillingSupport.present(r.data)]..sort(
      (a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
    );
  }

  Future<Map<String, Object?>> createCategory(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingSettingsManage);
    final r = BodyReader(body)..rejectUnknown({'name', 'description'});
    final name = r.str('name', min: 2, max: 60);
    final description = r.str('description', max: 200, required: false);
    r.throwIfInvalid();
    final key = name!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final id = 'ecat_${newId(length: 10)}';
    final now = _s.d.now;
    final existing = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'expense_categories'),
        filters: [QueryFilter('nameLower', FilterOp.eq, key)],
        limit: 1,
      ),
    );
    if (existing.isNotEmpty) {
      throw const ApiException.conflict('A category with this name exists.');
    }
    final doc = <String, Object?>{
      'categoryId': id,
      'tenantId': t.tenantId,
      'name': name,
      'nameLower': key,
      'description': description,
      'status': 'active',
      'createdAt': now,
      'createdBy': t.uid,
      'updatedAt': now,
    }..removeWhere((k, v) => v == null);
    await _s.d.store.commit([
      CreateOp(_s.path(t, 'expense_categories', id), doc),
      _s.audit(
        t,
        action: 'expense_category.created',
        resourceType: 'expense_category',
        resourceId: id,
        requestId: requestId,
        after: {'name': name},
      ),
    ]);
    return BillingSupport.present(doc);
  }

  Future<Map<String, Object?>> updateCategory(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingSettingsManage);
    final p = _s.path(t, 'expense_categories', id);
    final cur = await _s.d.store.get(p);
    if (cur == null) throw const ApiException.notFound('Category not found.');
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'name', 'description', 'status'});
    final name = r.str('name', min: 2, max: 60, required: false);
    final description = r.str('description', max: 200, required: false);
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    r.throwIfInvalid();
    final patch = <String, Object?>{
      'name': ?name,
      if (name != null)
        'nameLower': name.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      'description': ?description,
      'status': ?status,
      'updatedAt': _s.d.now,
    };
    await _s.d.store.commit([
      UpdateOp(p, patch),
      _s.audit(
        t,
        action: 'expense_category.updated',
        resourceType: 'expense_category',
        resourceId: id,
        requestId: requestId,
        after: {'fields': patch.keys.toList()},
      ),
    ]);
    return BillingSupport.present({...cur, ...patch});
  }

  // ----------------------------------------------------------- helpers

  Future<DocData> load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final e = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (e == null) throw const ApiException.notFound('Expense not found.');
    final b = e['branchId'] as String?;
    if (b == null ? !t.scope.allBranches : !t.scope.allows(b)) {
      throw const ApiException.notFound('Expense not found.');
    }
    return e;
  }

  Map<String, Object?> _event(TenantContext t, String status, {String? note}) =>
      {
        'status': status,
        'by': t.uid,
        'role': t.role.wireName,
        'at': _s.d.now,
        'note': note,
      }..removeWhere((k, v) => v == null);

  List<Object?> _history(DocData e, Map<String, Object?> ev) => [
    ...((e['history'] as List?) ?? const []),
    ev,
  ];

  static const Set<String> _fields = {
    'branchId',
    'categoryId',
    'description',
    'amountMinor',
    'expenseDate',
    'vendor',
    'method',
    'receiptReference',
    'evidenceNote',
  };

  Future<Map<String, Object?>> _parse(
    TenantContext t,
    BodyReader r, {
    required bool partial,
  }) async {
    final branchId = r.str('branchId', max: 40, required: false);
    final categoryId = r.str('categoryId', max: 40, required: !partial);
    final description = r.str(
      'description',
      min: 3,
      max: 300,
      required: !partial,
    );
    final amount = r.integer(
      'amountMinor',
      min: 1,
      max: 100000000000,
      required: !partial,
    );
    String? date;
    if (r.has('expenseDate') || !partial) {
      if (!Dates.valid(r.body['expenseDate'])) {
        r.addIssue('expenseDate', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        date = r.body['expenseDate'] as String;
      }
    }
    final vendor = r.str('vendor', max: 120, required: false);
    final methods = await _s.allowedMethods(t);
    final method = r.str('method', max: 30, required: false);
    if (method != null && !methods.contains(method)) {
      r.addIssue('method', 'unsupported', 'Use one of: ${methods.join(', ')}.');
    }
    final receipt = r.str('receiptReference', max: 100, required: false);
    final evidence = r.str('evidenceNote', max: 300, required: false);
    r.throwIfInvalid();
    String? categoryName;
    if (categoryId != null) {
      final c = await _s.d.store.get(
        _s.path(t, 'expense_categories', categoryId),
      );
      if (c == null || c['status'] != 'active') {
        throw const ApiException.notFound('Expense category not found.');
      }
      categoryName = c['name'] as String?;
    }
    // no branch means a clinic-wide expense, which needs all-branch access
    if (r.has('branchId') || !partial) {
      _s.requireBranchOrClinicWide(t, branchId);
      if (branchId != null &&
          await _s.d.store.get(_s.path(t, 'branches', branchId)) == null) {
        throw const ApiException.notFound('Branch not found.');
      }
    }
    return {
      if (r.has('branchId')) 'branchId': branchId,
      'categoryId': ?categoryId,
      'categoryName': ?categoryName,
      'description': ?description,
      'amount': ?amount,
      'expenseDate': ?date,
      'vendor': ?vendor,
      'method': ?method,
      'receiptReference': ?receipt,
      'evidenceNote': ?evidence,
    };
  }

  // ------------------------------------------------------------ create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expenseCreate);
    final r = BodyReader(body)..rejectUnknown(_fields);
    final f = await _parse(t, r, partial: false);
    final id = 'exp_${newId(length: 14)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'expenseId': id,
      'tenantId': t.tenantId,
      'branchId': null,
      ...f,
      'currency': await _s.currency(t),
      'status': 'draft',
      'history': [_event(t, 'draft')],
      'rev': 1,
      'createdAt': now,
      'createdBy': t.uid,
      'createdByRole': t.role.wireName,
      'updatedAt': now,
    };
    await _s.d.store.commit([
      CreateOp(_s.path(t, collection, id), doc),
      _s.audit(
        t,
        action: 'expense.created',
        resourceType: 'expense',
        resourceId: id,
        branchId: doc['branchId'] as String?,
        amount: doc['amount'] as int,
        requestId: requestId,
      ),
    ]);
    return BillingSupport.present(doc);
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expenseEdit);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({..._fields, 'expectedRev'});
    final expected = r.integer(
      'expectedRev',
      min: 1,
      max: 1000000,
      required: false,
    );
    final f = await _parse(t, r, partial: true);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final e = await load(t, id, tx: tx);
      if (e['status'] != 'draft' && e['status'] != 'rejected') {
        throw ApiException.conflict(
          'A ${e['status']} expense cannot be edited.',
        );
      }
      if (e['createdBy'] != t.uid && !t.can(ClinicPermission.expenseApprove)) {
        throw const ApiException.forbidden(
          'You can edit only your own expenses.',
        );
      }
      if (expected != null && expected != e['rev']) {
        throw const ApiException.conflict(
          'This expense changed since you opened it. Reload and try again.',
        );
      }
      final patch = <String, Object?>{
        ...f,
        if (e['status'] == 'rejected') ...{
          'status': 'draft',
          'history': _history(
            e,
            _event(t, 'draft', note: 'edited after rejection'),
          ),
        },
        'rev': ((e['rev'] as int?) ?? 1) + 1,
        'updatedAt': now,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'expense.updated',
          resourceType: 'expense',
          resourceId: id,
          branchId: (patch['branchId'] ?? e['branchId']) as String?,
          amount: (patch['amount'] ?? e['amount']) as int,
          requestId: requestId,
          before: {'amount': e['amount']},
          after: {'amount': patch['amount'] ?? e['amount']},
        ),
      ]);
      return BillingSupport.present({...e, ...patch});
    });
  }

  // -------------------------------------------------------- transitions

  Future<Map<String, Object?>> submit(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expenseCreate);
    return _transition(
      t,
      id,
      'submitted',
      allowedFrom: const {'draft'},
      requestId: requestId,
      check: (e) {
        if (e['createdBy'] != t.uid) {
          throw const ApiException.forbidden(
            'Only the creator can submit an expense.',
          );
        }
      },
      extra: (e) => {'submittedBy': t.uid, 'submittedAt': _s.d.now},
    );
  }

  Future<Map<String, Object?>> approve(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expenseApprove);
    final r = BodyReader(body)..rejectUnknown({'notes'});
    final notes = r.str('notes', max: 300, required: false);
    r.throwIfInvalid();
    final settings = await _s.settings(t);
    return _transition(
      t,
      id,
      'approved',
      allowedFrom: const {'submitted'},
      requestId: requestId,
      note: notes,
      check: (e) {
        if ((e['submittedBy'] == t.uid || e['createdBy'] == t.uid) &&
            settings['allowSelfApproval'] != true) {
          throw const ApiException.forbidden(
            'You cannot approve your own expense.',
          );
        }
        final limits = (settings['expenseApprovalLimits'] as Map?) ?? const {};
        final limit = limits[t.role.wireName];
        if (limit is int && (e['amount']! as int) > limit) {
          throw ApiException.forbidden(
            'This expense is above your approval limit of $limit.',
          );
        }
      },
      extra: (e) => {'approvedBy': t.uid, 'approvedAt': _s.d.now},
    );
  }

  Future<Map<String, Object?>> reject(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expenseReject);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    return _transition(
      t,
      id,
      'rejected',
      allowedFrom: const {'submitted'},
      requestId: requestId,
      note: reason,
      extra: (e) => {
        'rejectedBy': t.uid,
        'rejectedAt': _s.d.now,
        'rejectReason': reason,
      },
    );
  }

  /// Records that an approved expense was paid.
  Future<Map<String, Object?>> pay(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.expensePay);
    final r = BodyReader(body)
      ..rejectUnknown({'method', 'reference', 'paidDate'});
    final methods = await _s.allowedMethods(t);
    final method = r.str('method', max: 30);
    if (method != null && !methods.contains(method)) {
      r.addIssue('method', 'unsupported', 'Use one of: ${methods.join(', ')}.');
    }
    final reference = r.str('reference', max: 100, required: false);
    String? paidDate;
    if (r.has('paidDate')) {
      if (!Dates.valid(r.body['paidDate'])) {
        r.addIssue('paidDate', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        paidDate = r.body['paidDate'] as String;
      }
    }
    r.throwIfInvalid();
    final today = (await _s.zone(t)).localDate(_s.d.now);
    return _transition(
      t,
      id,
      'paid',
      allowedFrom: const {'approved'},
      requestId: requestId,
      extra: (e) => {
        'paidBy': t.uid,
        'paidAt': _s.d.now,
        'paidDate': paidDate ?? today,
        'paidMethod': method,
        'paidReference': reference,
      }..removeWhere((k, v) => v == null),
    );
  }

  Future<Map<String, Object?>> _transition(
    TenantContext t,
    String id,
    String to, {
    required Set<String> allowedFrom,
    String? requestId,
    String? note,
    void Function(DocData e)? check,
    Map<String, Object?> Function(DocData e)? extra,
  }) {
    return _s.d.store.transaction((tx) async {
      final e = await load(t, id, tx: tx);
      if (e['status'] == to) {
        return {...BillingSupport.present(e), 'idempotentReplay': true};
      }
      if (!allowedFrom.contains(e['status'])) {
        throw ApiException.conflict(
          'A ${e['status']} expense cannot become $to.',
        );
      }
      check?.call(e);
      final patch = <String, Object?>{
        'status': to,
        ...?extra?.call(e),
        'history': _history(e, _event(t, to, note: note)),
        'rev': ((e['rev'] as int?) ?? 1) + 1,
        'updatedAt': _s.d.now,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'expense.$to',
          resourceType: 'expense',
          resourceId: id,
          branchId: e['branchId'] as String?,
          amount: e['amount'] as int,
          reason: to == 'rejected' ? note : null,
          requestId: requestId,
          before: {'status': e['status']},
        ),
      ]);
      return BillingSupport.present({...e, ...patch});
    });
  }

  // -------------------------------------------------------------- reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.expenseView);
    return BillingSupport.present(await load(t, id));
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? status,
    String? categoryId,
    String? branchId,
    String? from,
    String? to,
  }) async {
    t.require(ClinicPermission.expenseView);
    if (status != null && !expenseStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    for (final v in [from, to]) {
      if (v != null && !Dates.valid(v)) {
        throw const ApiException.badRequest('from/to must be YYYY-MM-DD.');
      }
    }
    // Clinic-wide expenses (no branch) are visible with all-branch access only.
    final filters = <QueryFilter>[
      ..._s.scopeFilters(t, branchId),
      if (status != null) QueryFilter('status', FilterOp.eq, status),
      if (categoryId != null)
        QueryFilter('categoryId', FilterOp.eq, categoryId),
      if (from != null) QueryFilter('expenseDate', FilterOp.gte, from),
      if (to != null) QueryFilter('expenseDate', FilterOp.lte, to),
    ];
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: filters,
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }
}
