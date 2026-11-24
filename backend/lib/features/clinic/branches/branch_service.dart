import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:country_config/country_config.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';
import '../../platform/countries/country_rules.dart';
import '../common/clinic_deps.dart';
import '../common/seat_service.dart';
import '../common/tenant_context.dart';
import '../settings/operating_hours.dart';

const List<String> branchTypes = [
  'main',
  'satellite',
  'clinic',
  'diagnostic',
  'other',
];
const List<String> branchStatuses = ['active', 'inactive', 'suspended'];

/// Branches of one tenant. Branches are never deleted; deactivation keeps the
/// record and everything that references it.
class BranchService {
  BranchService(this._d);

  final ClinicDeps _d;

  static const String collection = 'branches';
  static const Set<String> fields = {
    'name',
    'code',
    'type',
    'email',
    'phone',
    'address',
    'timezone',
    'weeklyHours',
  };

  FieldIssue _issue(String f, String c, String m) =>
      FieldIssue(field: f, code: c, message: m);

  /// Parses create (`partial=false`) / update (`partial=true`) bodies.
  Map<String, Object?> _parse(
    Map<String, Object?> body, {
    required bool partial,
    CountryRules rules = const CountryRules(null),
  }) {
    final r = BodyReader(body, partial: partial)..rejectUnknown(fields);
    final name = r.str('name', min: 2, max: 80);
    var code = r.str('code', min: 2, max: 12);
    if (code != null) {
      code = code.toUpperCase();
      if (!RegExp(r'^[A-Z0-9\-]{2,12}$').hasMatch(code)) {
        r.addIssue(
          'code',
          'invalid_format',
          'Code may contain letters, digits and hyphens.',
        );
      }
    }
    final type = r.str('type', max: 20);
    if (type != null && !branchTypes.contains(type)) {
      r.addIssue(
        'type',
        'invalid_value',
        'type must be one of: ${branchTypes.join(', ')}.',
      );
    }
    final email = r.email('email', required: false);
    final phone = rules.phone(r, 'phone', required: false);
    final tz = r.str('timezone', max: 64, required: false);
    if (tz != null && !Timezones.isValid(tz)) {
      r.addIssue(
        'timezone',
        'invalid_timezone',
        'Use an IANA time zone such as Asia/Kolkata or Asia/Dubai.',
      );
    }
    Map<String, Object?>? address;
    final a = r.object('address', required: !partial);
    if (a != null) {
      a.rejectUnknown({
        'line1',
        'line2',
        'city',
        'state',
        'country',
        'countryCode',
        'postalCode',
        'localized',
      });
      final suppliedCode = a.str(
        'countryCode',
        min: 2,
        max: 2,
        required: false,
      );
      final country = rules.profile == null
          ? a.str('country', min: 2, max: 60)
          : a.str('country', min: 2, max: 60, required: false);
      final postal = rules.postal(
        a,
        a.str(
          'postalCode',
          min: 3,
          max: 10,
          required: rules.profile != null && rules.profile!.postalCode.required,
        ),
        legacyCountryText: country,
      );
      final canonical = rules.canonicalCountry(
        a,
        suppliedCode: suppliedCode,
        suppliedName: country,
      );
      final localized = readLocalizedAddress(a);
      address = {
        for (final e in {
          'line1': a.str('line1', min: 3, max: 120),
          'line2': a.str('line2', max: 120, required: false),
          'city': a.str('city', min: 2, max: 60),
          'state': a.str('state', min: 2, max: 60),
          ...canonical,
          'postalCode': postal,
          'localized': localized,
        }.entries)
          if (e.value != null) e.key: e.value,
      };
    }
    Map<String, Object?>? weekly;
    var weeklyGiven = false;
    if (body.containsKey('weeklyHours')) {
      weeklyGiven = true;
      weekly = body['weeklyHours'] == null
          ? null
          : HoursParser(r).weekly(body['weeklyHours'], 'weeklyHours');
    }
    r.throwIfInvalid();
    return {
      'name': ?name,
      'code': ?code,
      'type': ?type,
      'email': ?email,
      'phone': ?phone,
      'timezone': ?tz,
      'address': ?address,
      // null weeklyHours = use the clinic's hours
      if (weeklyGiven) 'weeklyHours': weekly,
    };
  }

  Future<int> _activeCount(TxContext? tx, TenantContext t) async {
    final q = DocQuery(
      _d.path(t, collection),
      filters: const [QueryFilter('status', FilterOp.eq, 'active')],
    );
    return tx == null ? _d.store.count(q) : (await tx.query(q)).length;
  }

  // ----------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.branchesCreate);
    if (!t.scope.allBranches) {
      throw const ApiException.forbidden(
        'Only users with access to all branches can create branches.',
      );
    }
    final rules = CountryRules(await _d.countries.tenantProfile(t.tenantId));
    final input = _parse(body, partial: false, rules: rules);
    final code = input['code']! as String;
    if (await _d.store.get(_d.path(t, 'branch_codes', code)) != null) {
      throw const ApiException.conflict('That branch code is already in use.');
    }
    final active = await _activeCount(null, t);
    if (active >= 1 &&
        t.entitlements.features[FeatureKey.multipleBranches] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include multiple branches.',
      );
    }
    final id = 'br_${newId(length: 12)}';
    final now = _d.now;
    final doc = <String, Object?>{
      'branchId': id,
      'tenantId': t.tenantId,
      ...input,
      'weeklyHours': input['weeklyHours'],
      'status': 'active',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
    };
    return _d.seats.withSeat(
      tenantId: t.tenantId,
      kind: SeatKind.branches,
      limit: t.entitlements.limits[LimitKey.maxBranches],
      entityId: id,
      build: (tx, slot) async => (
        present(doc),
        [
          CreateOp(_d.path(t, collection, id), {...doc, 'seatSlot': slot}),
          CreateOp(_d.path(t, 'branch_codes', code), {
            'branchId': id,
            'createdAt': now,
          }),
          _d.audit.op(
            AuditEntry(
              actor: _d.actorOf(t),
              action: 'branch.created',
              targetType: 'branch',
              targetId: id,
              tenantId: t.tenantId,
              requestId: requestId,
              after: {'name': input['name'], 'code': code},
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.branchesUpdate);
    t.scope.require(id);
    final rules = CountryRules(await _d.countries.tenantProfile(t.tenantId));
    final input = _parse(body, partial: true, rules: rules);
    if (input.isEmpty) {
      throw const ApiException.badRequest('No branch fields to update.');
    }
    if (input.containsKey('code')) {
      throw ApiException.validation([
        _issue('code', 'immutable', 'The branch code cannot be changed.'),
      ]);
    }
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) throw const ApiException.notFound('Branch not found.');
      final patch = {...input, 'updatedAt': now, 'updatedBy': t.uid};
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'branch.updated',
            targetType: 'branch',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'fields': input.keys.toList()},
          ),
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  // ------------------------------------------------------------ activation

  Future<Map<String, Object?>> activate(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.branchesActivate);
    t.scope.require(id);
    final head = await _d.store.get(_d.path(t, collection, id));
    if (head == null) throw const ApiException.notFound('Branch not found.');
    if (head['status'] == 'active') {
      throw const ApiException.conflict('Branch is already active.');
    }
    if (head['status'] == 'suspended') {
      throw const ApiException.conflict(
        'A suspended branch can only be reactivated by EazyClinic support.',
      );
    }
    if (await _activeCount(null, t) >= 1 &&
        t.entitlements.features[FeatureKey.multipleBranches] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include multiple branches.',
      );
    }
    final now = _d.now;
    return _d.seats.withSeat(
      tenantId: t.tenantId,
      kind: SeatKind.branches,
      limit: t.entitlements.limits[LimitKey.maxBranches],
      entityId: id,
      build: (tx, slot) async {
        final cur = await tx.get(_d.path(t, collection, id));
        if (cur == null || cur['status'] != 'inactive') {
          throw const ApiException.conflict('Branch cannot be activated.');
        }
        final patch = {
          'status': 'active',
          'seatSlot': slot,
          'updatedAt': now,
          'updatedBy': t.uid,
        };
        return (
          present({...cur, ...patch}),
          [
            UpdateOp(_d.path(t, collection, id), patch),
            _d.audit.op(
              AuditEntry(
                actor: _d.actorOf(t),
                action: 'branch.activated',
                targetType: 'branch',
                targetId: id,
                tenantId: t.tenantId,
                requestId: requestId,
                before: {'status': 'inactive'},
                after: {'status': 'active'},
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, Object?>> deactivate(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.branchesDeactivate);
    t.scope.require(id);
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) throw const ApiException.notFound('Branch not found.');
      if (cur['status'] != 'active') {
        throw const ApiException.conflict(
          'Only an active branch can be deactivated.',
        );
      }
      final active = await tx.query(
        DocQuery(
          _d.path(t, collection),
          filters: const [QueryFilter('status', FilterOp.eq, 'active')],
          limit: 2,
        ),
      );
      if (active.length < 2) {
        throw const ApiException.conflict(
          'A clinic needs at least one active branch.',
        );
      }
      final patch = {
        'status': 'inactive',
        'seatSlot': null,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      final release = _d.seats.release(
        t.tenantId,
        SeatKind.branches,
        cur['seatSlot'],
      );
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        ?release,
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'branch.deactivated',
            targetType: 'branch',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            before: {'status': 'active'},
            after: {'status': 'inactive'},
          ),
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  // ------------------------------------------------------------------ reads

  Future<Map<String, Object?>?> find(TenantContext t, String id) =>
      _d.store.get(_d.path(t, collection, id));

  /// Branch exists in this tenant and is active (used by other services).
  Future<Map<String, Object?>> requireActive(TenantContext t, String id) async {
    final b = await find(t, id);
    if (b == null) throw const ApiException.notFound('Branch not found.');
    if (b['status'] != 'active') {
      throw const ApiException.conflict('The branch is not active.');
    }
    return b;
  }

  Future<Paged> list(
    TenantContext t,
    Request request, {
    String? status,
    String? q,
  }) async {
    t.require(ClinicPermission.branchesView);
    final query = q?.trim().toLowerCase();
    final filter = status == null ? null : (status);
    if (filter != null && !branchStatuses.contains(filter)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (t.scope.allBranches) {
      return runPaged(
        _d.store,
        DocQuery(
          _d.path(t, collection),
          filters: [
            if (filter != null) QueryFilter('status', FilterOp.eq, filter),
          ],
          orderBy: const OrderBy('createdAt', descending: true),
        ),
        request,
      ).then(
        (p) => query == null || query.isEmpty
            ? p
            : Paged(
                p.docs.where((d) => _matches(d.data, query)).toList(),
                p.meta,
              ),
      );
    }
    // Scoped users: fetch only the branches in their scope.
    final docs = <StoredDoc>[];
    for (final id in t.scope.branchIds.take(100)) {
      final d = await find(t, id);
      if (d != null &&
          (filter == null || d['status'] == filter) &&
          (query == null || query.isEmpty || _matches(d, query))) {
        docs.add(StoredDoc(_d.path(t, collection, id), d));
      }
    }
    docs.sort((a, b) => '${a.data['name']}'.compareTo('${b.data['name']}'));
    return Paged(docs, const PageMeta(limit: 100, hasMore: false));
  }

  bool _matches(Map<String, Object?> b, String q) =>
      '${b['name']}'.toLowerCase().contains(q) ||
      '${b['code']}'.toLowerCase().contains(q);

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.branchesView);
    t.scope.require(id);
    final b = await find(t, id);
    if (b == null) throw const ApiException.notFound('Branch not found.');
    final assignments = await _d.store.query(
      DocQuery(
        _d.path(t, 'doctor_branch_assignments'),
        filters: [
          QueryFilter('branchId', FilterOp.eq, id),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 50,
      ),
    );
    final doctors = <Map<String, Object?>>[];
    if (t.can(ClinicPermission.doctorsView)) {
      for (final a in assignments) {
        final doc = await _d.store.get(
          _d.path(t, 'doctors', a.data['doctorId']! as String),
        );
        if (doc != null) {
          doctors.add({
            'doctorId': doc['doctorId'],
            'fullName': doc['fullName'],
            'specialty': doc['specialty'],
          });
        }
      }
    }
    final staff = <Map<String, Object?>>[];
    if (t.can(ClinicPermission.staffView)) {
      final specific = await _d.store.query(
        DocQuery(
          _d.path(t, 'staff'),
          filters: [QueryFilter('branchIds', FilterOp.arrayContains, id)],
          limit: 50,
        ),
      );
      final everywhere = await _d.store.query(
        DocQuery(
          _d.path(t, 'staff'),
          filters: const [QueryFilter('allBranches', FilterOp.eq, true)],
          limit: 50,
        ),
      );
      for (final s in [...specific, ...everywhere]) {
        staff.add({
          'staffId': s.data['staffId'],
          'fullName': s.data['fullName'],
          'role': s.data['role'],
          'status': s.data['status'],
        });
      }
    }
    return {...present(b), 'doctors': doctors, 'staff': staff};
  }

  static Map<String, Object?> present(Map<String, Object?> b) =>
      (jsonSafe(b)! as Map<String, Object?>)..remove('seatSlot');
}
