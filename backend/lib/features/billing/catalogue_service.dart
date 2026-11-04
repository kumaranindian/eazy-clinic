import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/time_support.dart';
import 'billing_math.dart';
import 'billing_support.dart';

const List<String> serviceCategories = [
  'consultation',
  'follow_up_consultation',
  'registration',
  'procedure',
  'diagnostic',
  'laboratory',
  'custom',
];

const Set<String> _consultationCategories = {
  'consultation',
  'follow_up_consultation',
};

/// Billing settings, tax rules and the service/charge catalogue.
///
/// Tax rules are plain configuration entered by the clinic. The product does
/// not ship rates and makes no claim that a configuration is correct for any
/// tax regime; the clinic's accountant must validate it.
class CatalogueService {
  CatalogueService(this._s);

  final BillingSupport _s;

  // ---------------------------------------------------------- settings

  Future<Map<String, Object?>> getSettings(TenantContext t) async {
    t.require(ClinicPermission.billingView);
    final s = await _s.settings(t);
    return {
      ...BillingSupport.present(s),
      'currency': await _s.currency(t),
      'paymentMethods': await _s.allowedMethods(t),
    };
  }

  Future<Map<String, Object?>> updateSettings(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingSettingsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({
        'invoiceDueDays',
        'customPaymentMethods',
        'discountLimitsBps',
        'expenseApprovalLimits',
        'allowSelfApproval',
      });
    final patch = <String, Object?>{};
    final due = r.integer('invoiceDueDays', min: 0, max: 365, required: false);
    if (due != null) patch['invoiceDueDays'] = due;
    final self = r.boolean('allowSelfApproval');
    if (self != null) patch['allowSelfApproval'] = self;
    if (r.has('customPaymentMethods')) {
      final raw = r.body['customPaymentMethods'];
      final ok =
          raw is List &&
          raw.length <= 10 &&
          raw.every(
            (e) =>
                e is String &&
                RegExp(r'^[a-z][a-z0-9_]{1,29}$').hasMatch(e) &&
                !paymentMethods.contains(e) &&
                e != 'online' &&
                e != 'razorpay',
          );
      if (!ok) {
        r.addIssue(
          'customPaymentMethods',
          'invalid_value',
          'Give up to 10 lowercase method names (letters, digits, _). '
              'Built-in and gateway methods cannot be redefined.',
        );
      } else {
        patch['customPaymentMethods'] = raw;
      }
    }
    Map<String, Object?>? mapOf(String f, int max) {
      if (!r.has(f)) return null;
      final raw = r.body[f];
      if (raw is! Map ||
          raw.length > 20 ||
          raw.entries.any(
            (e) =>
                ClinicRole.tryParse('${e.key}') == null ||
                e.value is! int ||
                (e.value as int) < 0 ||
                (e.value as int) > max,
          )) {
        r.addIssue(f, 'invalid_value', 'Give role names with whole numbers.');
        return null;
      }
      return raw.cast<String, Object?>();
    }

    final disc = mapOf('discountLimitsBps', 10000);
    if (disc != null) patch['discountLimitsBps'] = disc;
    final lim = mapOf('expenseApprovalLimits', 100000000000);
    if (lim != null) patch['expenseApprovalLimits'] = lim;
    r.throwIfInvalid();
    if (patch.isEmpty) return getSettings(t);
    final p = _s.path(t, 'billing_settings', 'main');
    final existing = await _s.d.store.get(p);
    final now = _s.d.now;
    patch
      ..['updatedAt'] = now
      ..['updatedBy'] = t.uid;
    await _s.d.store.commit([
      existing == null ? CreateOp(p, patch) : UpdateOp(p, patch),
      _s.audit(
        t,
        action: 'billing.settings_updated',
        resourceType: 'billing_settings',
        resourceId: 'main',
        requestId: requestId,
        after: {
          'fields': patch.keys.where((k) => !k.startsWith('updated')).toList(),
        },
      ),
    ]);
    return getSettings(t);
  }

  // --------------------------------------------------------- tax rules

  Future<TaxRule?> taxRule(
    TenantContext t,
    String? id, {
    TxContext? tx,
    bool mustBeActive = true,
  }) async {
    if (id == null) return null;
    final p = _s.path(t, 'tax_rules', id);
    final d = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (d == null) throw const ApiException.notFound('Tax rule not found.');
    if (mustBeActive && d['status'] != 'active') {
      throw const ApiException.conflict('This tax rule is inactive.');
    }
    return ruleFrom(d);
  }

  static TaxRule ruleFrom(Map<String, Object?> d) => TaxRule(
    id: '${d['taxRuleId']}',
    name: '${d['name']}',
    inclusive: d['inclusive'] == true,
    components: [
      for (final c in (d['components'] as List? ?? const []))
        TaxComponent('${(c as Map)['name']}', c['rateBps'] as int),
    ],
  );

  Future<List<Map<String, Object?>>> listTaxRules(TenantContext t) async {
    t.require(ClinicPermission.billingView);
    final rows = await _s.d.store.query(
      DocQuery(_s.path(t, 'tax_rules'), limit: 100),
    );
    return [for (final r in rows) BillingSupport.present(r.data)];
  }

  List<Map<String, Object?>>? _components(BodyReader r) {
    if (!r.has('components')) {
      if (!r.partial) {
        r.addIssue('components', 'required', 'components is required.');
      }
      return null;
    }
    final raw = r.body['components'];
    if (raw is! List || raw.isEmpty || raw.length > 5) {
      r.addIssue('components', 'invalid_value', 'Give 1 to 5 tax components.');
      return null;
    }
    final out = <Map<String, Object?>>[];
    var total = 0;
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('components[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final c = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({'name', 'rateBps'});
      final name = c.str('name', min: 2, max: 30);
      final rate = c.integer('rateBps', min: 0, max: 10000);
      for (final x in c.issues) {
        r.addIssue('components[$i].${x.field}', x.code, x.message);
      }
      total += rate ?? 0;
      out.add({'name': name, 'rateBps': rate});
    }
    if (total > 10000) {
      r.addIssue(
        'components',
        'invalid_value',
        'Total rate cannot exceed 100%.',
      );
    }
    return out;
  }

  Future<Map<String, Object?>> createTaxRule(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.serviceCatalogueManage);
    final r = BodyReader(body)
      ..rejectUnknown({'name', 'components', 'inclusive'});
    final name = r.str('name', min: 2, max: 60);
    final comps = _components(r);
    final inclusive = r.boolean('inclusive') ?? false;
    r.throwIfInvalid();
    final id = 'tx_${newId(length: 12)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'taxRuleId': id,
      'tenantId': t.tenantId,
      'name': name,
      'components': comps,
      'inclusive': inclusive,
      'status': 'active',
      'createdAt': now,
      'createdBy': t.uid,
      'updatedAt': now,
    };
    await _s.d.store.commit([
      CreateOp(_s.path(t, 'tax_rules', id), doc),
      _s.audit(
        t,
        action: 'tax_rule.created',
        resourceType: 'tax_rule',
        resourceId: id,
        requestId: requestId,
        after: {'name': name, 'inclusive': inclusive},
      ),
    ]);
    return BillingSupport.present(doc);
  }

  Future<Map<String, Object?>> updateTaxRule(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.serviceCatalogueManage);
    final p = _s.path(t, 'tax_rules', id);
    final cur = await _s.d.store.get(p);
    if (cur == null) throw const ApiException.notFound('Tax rule not found.');
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'name', 'components', 'inclusive', 'status'});
    final name = r.str('name', min: 2, max: 60, required: false);
    final comps = _components(r);
    final inclusive = r.boolean('inclusive');
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    r.throwIfInvalid();
    final patch = <String, Object?>{
      'name': ?name,
      'components': ?comps,
      'inclusive': ?inclusive,
      'status': ?status,
      'updatedAt': _s.d.now,
      'updatedBy': t.uid,
    };
    await _s.d.store.commit([
      UpdateOp(p, patch),
      _s.audit(
        t,
        action: 'tax_rule.updated',
        resourceType: 'tax_rule',
        resourceId: id,
        requestId: requestId,
        after: {'fields': patch.keys.toList()},
      ),
    ]);
    return BillingSupport.present({...cur, ...patch});
  }

  // ---------------------------------------------------------- services

  static String _lower(String v) =>
      v.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, int>? _priceMap(BodyReader r, String f, int maxEntries) {
    if (!r.has(f)) return null;
    final raw = r.body[f];
    if (raw is! Map ||
        raw.length > maxEntries ||
        raw.entries.any(
          (e) =>
              e.value is! int ||
              (e.value as int) < 0 ||
              (e.value as int) > 1000000000 ||
              '${e.key}'.length > 40,
        )) {
      r.addIssue(f, 'invalid_value', 'Give ids with amounts in minor units.');
      return null;
    }
    return {for (final e in raw.entries) '${e.key}': e.value as int};
  }

  List<String>? _idList(BodyReader r, String f, int max) {
    if (!r.has(f)) return null;
    final raw = r.body[f];
    if (raw is! List ||
        raw.length > max ||
        raw.any((e) => e is! String || e.isEmpty || e.length > 40)) {
      r.addIssue(f, 'invalid_value', 'Give up to $max ids.');
      return null;
    }
    return raw.cast<String>();
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.serviceCatalogueManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'name',
        'description',
        'category',
        'amountMinor',
        'taxRuleId',
        'branchIds',
        'doctorIds',
        'branchPrices',
        'doctorFees',
        'effectiveFrom',
      });
    final f = await _parse(t, r, partial: false);
    final id = 'svc_${newId(length: 12)}';
    final now = _s.d.now;
    final today = (await _s.zone(t)).localDate(now);
    final currency = await _s.currency(t);
    final doc = <String, Object?>{
      'serviceId': id,
      'tenantId': t.tenantId,
      ...f,
      'nameLower': _lower('${f['name']}'),
      'currency': currency,
      'effectiveFrom': f['effectiveFrom'] ?? today,
      'status': 'active',
      'version': 1,
      'createdAt': now,
      'createdBy': t.uid,
      'updatedAt': now,
      'updatedBy': t.uid,
    };
    await _s.d.store.commit([
      CreateOp(_s.path(t, 'service_catalogue', id), doc),
      _history(t, doc, 'created'),
      _s.audit(
        t,
        action: 'service.created',
        resourceType: 'service',
        resourceId: id,
        requestId: requestId,
        amount: doc['amountMinor'] as int?,
        after: {'name': doc['name'], 'category': doc['category']},
      ),
    ]);
    return BillingSupport.present(doc);
  }

  CreateOp _history(
    TenantContext t,
    Map<String, Object?> svc,
    String change, {
    String? reason,
  }) => CreateOp(_s.path(t, 'service_price_history', newId()), {
    'serviceId': svc['serviceId'],
    'version': svc['version'],
    'change': change,
    'amountMinor': svc['amountMinor'],
    'currency': svc['currency'],
    'taxRuleId': svc['taxRuleId'],
    'branchPrices': svc['branchPrices'],
    'doctorFees': svc['doctorFees'],
    'status': svc['status'],
    'effectiveFrom': svc['effectiveFrom'],
    'reason': reason,
    'changedBy': t.uid,
    'changedAt': _s.d.now,
  });

  Future<Map<String, Object?>> _parse(
    TenantContext t,
    BodyReader r, {
    required bool partial,
  }) async {
    final name = r.str('name', min: 2, max: 120, required: !partial);
    final description = r.str('description', max: 500, required: false);
    final category = r.enumOf<String>(
      'category',
      serviceCategories,
      (v) => v,
      required: !partial,
    );
    final amount = r.integer(
      'amountMinor',
      min: 0,
      max: 1000000000,
      required: !partial,
    );
    final ruleId = r.str('taxRuleId', max: 40, required: false);
    final branchIds = _idList(r, 'branchIds', 50);
    final doctorIds = _idList(r, 'doctorIds', 100);
    final branchPrices = _priceMap(r, 'branchPrices', 50);
    final doctorFees = _priceMap(r, 'doctorFees', 100);
    String? effective;
    if (r.has('effectiveFrom')) {
      if (!Dates.valid(r.body['effectiveFrom'])) {
        r.addIssue('effectiveFrom', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        effective = r.body['effectiveFrom'] as String;
      }
    }
    r.throwIfInvalid();
    if (ruleId != null) await taxRule(t, ruleId);
    for (final b in [...?branchIds, ...?branchPrices?.keys]) {
      t.scope.require(b);
      if (await _s.d.store.get(_s.path(t, 'branches', b)) == null) {
        throw const ApiException.notFound('Branch not found.');
      }
    }
    if (branchIds != null &&
        branchIds.isNotEmpty &&
        (branchPrices?.keys.any((k) => !branchIds.contains(k)) ?? false)) {
      throw ApiException.validation([
        billingIssue(
          'branchPrices',
          'invalid_value',
          'A branch price needs the branch in branchIds.',
        ),
      ]);
    }
    if (doctorFees != null &&
        category != null &&
        !_consultationCategories.contains(category)) {
      throw ApiException.validation([
        billingIssue(
          'doctorFees',
          'invalid_value',
          'Doctor fees apply to consultation services only.',
        ),
      ]);
    }
    return {
      'name': ?name,
      'description': ?description,
      'category': ?category,
      'amountMinor': ?amount,
      if (r.has('taxRuleId')) 'taxRuleId': ruleId,
      'branchIds': ?branchIds,
      'doctorIds': ?doctorIds,
      'branchPrices': ?branchPrices,
      'doctorFees': ?doctorFees,
      'effectiveFrom': ?effective,
    };
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.serviceCatalogueManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({
        'name',
        'description',
        'category',
        'amountMinor',
        'taxRuleId',
        'branchIds',
        'doctorIds',
        'branchPrices',
        'doctorFees',
        'effectiveFrom',
        'status',
        'reason',
      });
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    final reason = r.str('reason', max: 300, required: false);
    final fields = await _parse(t, r, partial: true);
    final p = _s.path(t, 'service_catalogue', id);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await tx.get(p);
      if (cur == null) throw const ApiException.notFound('Service not found.');
      final patch = <String, Object?>{
        ...fields,
        'status': ?status,
        if (fields['name'] != null) 'nameLower': _lower('${fields['name']}'),
        'version': ((cur['version'] as int?) ?? 1) + 1,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      final next = {...cur, ...patch};
      tx.write([
        UpdateOp(p, patch),
        _history(t, next, 'updated', reason: reason),
        _s.audit(
          t,
          action: 'service.updated',
          resourceType: 'service',
          resourceId: id,
          requestId: requestId,
          reason: reason,
          before: {'amountMinor': cur['amountMinor'], 'status': cur['status']},
          after: {'amountMinor': next['amountMinor'], 'status': next['status']},
        ),
      ]);
      return BillingSupport.present(next);
    });
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? q,
    String? category,
    String? status,
  }) async {
    t.require(ClinicPermission.billingView);
    if (category != null && !serviceCategories.contains(category)) {
      throw const ApiException.badRequest('category has an unsupported value.');
    }
    if (status != null && status != 'active' && status != 'inactive') {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    final term = q == null ? null : _lower(q);
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, 'service_catalogue'),
        filters: [
          if (category != null) QueryFilter('category', FilterOp.eq, category),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (term != null && term.isNotEmpty) ...[
            QueryFilter('nameLower', FilterOp.gte, term),
            QueryFilter('nameLower', FilterOp.lt, '$term'),
          ],
        ],
        orderBy: const OrderBy('nameLower'),
      ),
      req,
    );
  }

  Future<Map<String, Object?>> priceHistory(TenantContext t, String id) async {
    t.require(ClinicPermission.billingView);
    final svc = await _s.d.store.get(_s.path(t, 'service_catalogue', id));
    if (svc == null) throw const ApiException.notFound('Service not found.');
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'service_price_history'),
        filters: [QueryFilter('serviceId', FilterOp.eq, id)],
        limit: 200,
      ),
    );
    final items = [for (final r in rows) BillingSupport.present(r.data)]
      ..sort(
        (a, b) => ((a['version'] as int?) ?? 0).compareTo(
          (b['version'] as int?) ?? 0,
        ),
      );
    return {'serviceId': id, 'history': items};
  }

  /// The service for an invoice line, checked for use on [branchId] today.
  Future<DocData> usable(
    TenantContext t,
    String serviceId,
    String branchId,
    String? doctorId, {
    TxContext? tx,
  }) async {
    final p = _s.path(t, 'service_catalogue', serviceId);
    final s = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (s == null) throw const ApiException.notFound('Service not found.');
    if (s['status'] != 'active') {
      throw const ApiException.conflict('This service is inactive.');
    }
    final today = (await _s.zone(t)).localDate(_s.d.now);
    if (('${s['effectiveFrom']}').compareTo(today) > 0) {
      throw const ApiException.conflict('This service is not effective yet.');
    }
    final branches = (s['branchIds'] as List?) ?? const [];
    if (branches.isNotEmpty && !branches.contains(branchId)) {
      throw const ApiException.conflict(
        'This service is not offered at this branch.',
      );
    }
    final doctors = (s['doctorIds'] as List?) ?? const [];
    if (doctors.isNotEmpty &&
        (doctorId == null || !doctors.contains(doctorId))) {
      throw const ApiException.conflict(
        'This service is not offered by this doctor.',
      );
    }
    return s;
  }

  /// Doctor fee, else branch price, else default.
  static int priceFor(DocData service, String branchId, String? doctorId) {
    final fees = (service['doctorFees'] as Map?) ?? const {};
    if (doctorId != null && fees[doctorId] is int) return fees[doctorId] as int;
    final bp = (service['branchPrices'] as Map?) ?? const {};
    if (bp[branchId] is int) return bp[branchId] as int;
    return service['amountMinor'] as int;
  }
}
