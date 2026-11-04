import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../auth/domain/auth_context.dart';
import '../scheduling/slot_service.dart';
import 'portal_support.dart';

/// Clinic, doctor and speciality discovery for patients.
///
/// Only approved, active clinics whose plan includes the patient app are
/// shown, and only fields meant for the public: no staff, no registration
/// numbers, no internal settings. Nothing here reveals any patient record.
class PortalDiscoveryService {
  PortalDiscoveryService(this._s, this._slots);

  final PortalSupport _s;
  final SlotService _slots;

  static const int maxResults = 30;

  Future<Map<String, Object?>> _card(String tenantId, DocData tenant) async {
    final profile = await _s.store.get(
      _s.path(tenantId, 'clinic_settings', 'profile'),
    );
    return {
      'clinicId': tenantId,
      'name': profile?['name'] ?? tenant['clinicName'],
      'description': profile?['description'],
      'specialities': profile?['specialities'],
      'address': profile?['address'],
      'phone': profile?['phone'],
      'email': profile?['email'],
      'website': profile?['website'],
    }..removeWhere((k, v) => v == null);
  }

  Future<List<Map<String, Object?>>> clinics(
    AuthContext ctx, {
    String? q,
    String? city,
  }) async {
    await _s.accounts.requireAccount(ctx);
    final term = q?.trim().toLowerCase();
    final cityTerm = city?.trim().toLowerCase();
    final rows = await _s.store.query(
      DocQuery(
        'tenants',
        filters: [const QueryFilter('status', FilterOp.eq, 'active')],
        limit: 300,
      ),
    );
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      if (out.length >= maxResults) break;
      final name = '${r.data['clinicName'] ?? ''}'.toLowerCase();
      if (term != null && term.isNotEmpty && !name.contains(term)) continue;
      if (!await _s.discoverable(r.id)) continue;
      final card = await _card(r.id, r.data);
      if (cityTerm != null && cityTerm.isNotEmpty) {
        final addr = '${card['address'] ?? ''}'.toLowerCase();
        if (!addr.contains(cityTerm)) continue;
      }
      out.add(card);
    }
    return out;
  }

  Future<DocData> _open(String clinicId) async {
    final t = await _s.store.get('tenants/$clinicId');
    if (t == null || !await _s.discoverable(clinicId)) {
      throw const ApiException.notFound('Clinic not found.');
    }
    return t;
  }

  Future<Map<String, Object?>> clinic(AuthContext ctx, String clinicId) async {
    await _s.accounts.requireAccount(ctx);
    final tenant = await _open(clinicId);
    final branches = await _s.store.query(
      DocQuery(
        _s.path(clinicId, 'branches'),
        filters: [const QueryFilter('status', FilterOp.eq, 'active')],
        limit: 50,
      ),
    );
    final types = await _s.store.query(
      DocQuery(
        _s.path(clinicId, 'appointment_types'),
        filters: [const QueryFilter('status', FilterOp.eq, 'active')],
        limit: 50,
      ),
    );
    final settings = await _s.store.get(
      _s.path(clinicId, 'clinic_settings', 'operations'),
    );
    return {
      ...await _card(clinicId, tenant),
      'workingHours': settings?['weeklyHours'],
      'timezone': settings?['timezone'],
      'branches': [
        for (final b in branches)
          PortalSupport.pick(b.data, [
            'branchId',
            'name',
            'address',
            'phone',
            'email',
            'workingHours',
            'timezone',
          ]),
      ],
      'appointmentTypes': [
        for (final t in types)
          PortalSupport.pick(t.data, [
            'typeId',
            'name',
            'durationMinutes',
            'description',
          ]),
      ],
      'bookingMethods': ['patient_app', 'reception'],
      'onlinePayments': false,
    };
  }

  static const List<String> _doctorFields = [
    'doctorId',
    'fullName',
    'designation',
    'qualifications',
    'specialty',
    'subSpecialty',
    'yearsOfExperience',
    'languages',
    'consultationFeeMinor',
    'biography',
  ];

  Future<List<Map<String, Object?>>> doctors(
    AuthContext ctx,
    String clinicId, {
    String? branchId,
    String? q,
    String? speciality,
  }) async {
    await _s.accounts.requireAccount(ctx);
    await _open(clinicId);
    final rows = await _s.store.query(
      DocQuery(
        _s.path(clinicId, 'doctors'),
        filters: [const QueryFilter('status', FilterOp.eq, 'active')],
        limit: 200,
      ),
    );
    final term = q?.trim().toLowerCase();
    final spec = speciality?.trim().toLowerCase();
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final d = r.data;
      final branches = ((d['branchIds'] as List?) ?? const []).cast<String>();
      if (branchId != null && !branches.contains(branchId)) continue;
      if (term != null &&
          term.isNotEmpty &&
          !'${d['fullName']}'.toLowerCase().contains(term)) {
        continue;
      }
      if (spec != null &&
          spec.isNotEmpty &&
          '${d['specialty'] ?? ''}'.toLowerCase() != spec) {
        continue;
      }
      out.add({
        ...PortalSupport.pick(d, _doctorFields),
        'doctorId': r.id,
        'branchIds': branches,
        'consultationModes': ['in_person'],
      });
    }
    out.sort((a, b) => '${a['fullName']}'.compareTo('${b['fullName']}'));
    return out;
  }

  Future<Map<String, Object?>> doctor(
    AuthContext ctx,
    String clinicId,
    String doctorId,
  ) async {
    final all = await doctors(ctx, clinicId);
    final hit = all.where((d) => d['doctorId'] == doctorId);
    if (hit.isEmpty) throw const ApiException.notFound('Doctor not found.');
    return hit.first;
  }

  Future<List<String>> specialities(AuthContext ctx, String clinicId) async {
    final all = await doctors(ctx, clinicId);
    return ({
      for (final d in all)
        if (d['specialty'] != null) '${d['specialty']}',
    }.toList()..sort());
  }

  /// Free slots from the same engine staff use; the backend recalculates them
  /// when booking, so this is a hint, never a promise.
  Future<Map<String, Object?>> availability(
    AuthContext ctx,
    String clinicId, {
    required String branchId,
    required String doctorId,
    required String date,
    String? typeId,
  }) async {
    await _s.accounts.requireAccount(ctx);
    await _open(clinicId);
    final t = await _s.actingIn(ctx, clinicId);
    return _slots.availableSlots(
      t,
      branchId: branchId,
      doctorId: doctorId,
      date: date,
      typeId: typeId,
    );
  }
}

/// Keeps `Request` imported for route code that reads query parameters.
typedef PortalRequest = Request;
