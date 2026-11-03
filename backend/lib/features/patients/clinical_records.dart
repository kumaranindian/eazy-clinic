import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../clinic/settings/operating_hours.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'consent_service.dart';
import 'patient_service.dart';
import 'patient_support.dart';

const List<String> recordSources = [
  'patient_reported',
  'caregiver_reported',
  'clinic_recorded',
  'imported',
];

const List<String> historyCategories = [
  'condition',
  'chronic_condition',
  'previous_illness',
  'surgery',
  'hospitalization',
  'family_history',
  'immunization',
  'lifestyle',
];

const List<String> alertCategories = [
  'medical',
  'allergy',
  'special_assistance',
  'communication',
  'administrative',
  'other',
];

/// One kind of clinic-recorded patient information (history entry, allergy,
/// medication, alert). All kinds share the same safety rules: tenant/branch
/// checks, source and verification tracking, revisions instead of overwrites,
/// consent for new processing, and audit.
class RecordSpec {
  const RecordSpec({
    required this.name,
    required this.collection,
    required this.idField,
    required this.idPrefix,
    required this.viewPermission,
    required this.managePermission,
    required this.fields,
    required this.parse,
    this.immutable = const {},
    this.listFilters = const {},
    this.normalize,
  });

  final String name;
  final String collection;
  final String idField;
  final String idPrefix;
  final String viewPermission;
  final String managePermission;
  final Set<String> fields;

  /// Fields that cannot change after creation.
  final Set<String> immutable;

  /// Query parameter → stored field filters accepted by list.
  final Map<String, List<String>> listFilters;

  /// Parses the kind-specific fields into stored values.
  final Map<String, Object?> Function(BodyReader r, {required bool partial})
  parse;

  /// Final adjustments once verification is known (e.g. allergy status).
  final Map<String, Object?> Function(Map<String, Object?> merged)? normalize;
}

String? _date(BodyReader r, String f, SpecClock clock) {
  if (!r.has(f) || r.body[f] == null) return null;
  final raw = r.body[f];
  if (!HoursParser.validDate(raw, minYear: 1900, maxYear: clock().year) ||
      DateTime.parse(raw! as String).isAfter(clock())) {
    r.addIssue(f, 'invalid_date', 'Enter a valid past date (YYYY-MM-DD).');
    return null;
  }
  return raw as String;
}

typedef SpecClock = DateTime Function();

/// The four record kinds. The clock is injected for date validation.
class RecordSpecs {
  RecordSpecs(this._clock);

  final SpecClock _clock;

  late final RecordSpec history = RecordSpec(
    name: 'history',
    collection: 'patient_history_entries',
    idField: 'entryId',
    idPrefix: 'he_',
    viewPermission: ClinicPermission.historyView,
    managePermission: ClinicPermission.historyManage,
    immutable: const {'category'},
    listFilters: const {
      'category': historyCategories,
      'status': ['active', 'resolved', 'inactive', 'entered_in_error'],
    },
    fields: const {
      'category',
      'title',
      'status',
      'code',
      'description',
      'onsetDate',
      'resolvedDate',
      'eventDate',
      'relative',
      'ageAtDiagnosis',
      'provider',
      'notes',
      'source',
      'verify',
      'markReviewed',
    },
    parse: (r, {required partial}) {
      final category = r.enumOf<String>(
        'category',
        historyCategories,
        (v) => v,
      );
      final title = r.str('title', min: 2, max: 120);
      final status = r.enumOf<String>(
        'status',
        const ['active', 'resolved', 'inactive', 'entered_in_error'],
        (v) => v,
        required: false,
      );
      final onset = _date(r, 'onsetDate', _clock);
      final resolved = _date(r, 'resolvedDate', _clock);
      if (onset != null && resolved != null && resolved.compareTo(onset) < 0) {
        r.addIssue(
          'resolvedDate',
          'invalid_period',
          'The resolution date cannot be before the onset date.',
        );
      }
      final relative = r.str('relative', min: 2, max: 40, required: false);
      if (category == 'family_history' && !partial && relative == null) {
        r.addIssue(
          'relative',
          'required',
          'Say which relative this applies to.',
        );
      }
      return {
        'category': ?category,
        'title': ?title,
        'status': status ?? (partial ? null : 'active'),
        'code': ?r.str('code', max: 30, required: false),
        'description': ?r.str('description', max: 500, required: false),
        'onsetDate': ?onset,
        'resolvedDate': ?resolved,
        'eventDate': ?_date(r, 'eventDate', _clock),
        'relative': ?relative,
        'ageAtDiagnosis': ?r.integer(
          'ageAtDiagnosis',
          min: 0,
          max: 120,
          required: false,
        ),
        'provider': ?r.str('provider', max: 120, required: false),
        'notes': ?r.str('notes', max: 1000, required: false),
      }..removeWhere((k, v) => v == null);
    },
  );

  late final RecordSpec allergy = RecordSpec(
    name: 'allergy',
    collection: 'patient_allergies',
    idField: 'allergyId',
    idPrefix: 'al_',
    viewPermission: ClinicPermission.allergiesView,
    managePermission: ClinicPermission.allergiesManage,
    listFilters: const {
      'status': ['active', 'inactive', 'unverified'],
    },
    fields: const {
      'allergen',
      'category',
      'reaction',
      'severity',
      'onsetDate',
      'status',
      'notes',
      'source',
      'verify',
      'markReviewed',
    },
    parse: (r, {required partial}) => {
      'allergen': ?r.str('allergen', min: 2, max: 100),
      'category': ?r.enumOf<String>('category', const [
        'drug',
        'food',
        'environmental',
        'insect',
        'latex',
        'other',
      ], (v) => v),
      'reaction': ?r.str('reaction', max: 200, required: false),
      'severity':
          r.enumOf<String>(
            'severity',
            const ['mild', 'moderate', 'severe', 'unknown'],
            (v) => v,
            required: false,
          ) ??
          (partial ? null : 'unknown'),
      'onsetDate': ?_date(r, 'onsetDate', _clock),
      'status': ?r.enumOf<String>(
        'status',
        const ['active', 'inactive', 'unverified'],
        (v) => v,
        required: false,
      ),
      'notes': ?r.str('notes', max: 1000, required: false),
    }..removeWhere((k, v) => v == null),
    // an allergy is only "active" once a clinician has verified it
    normalize: (m) {
      final verified = m['verificationStatus'] == 'verified';
      final cur = m['status'] as String?;
      final next = cur == null
          ? (verified ? 'active' : 'unverified')
          : cur == 'active' && !verified
          ? 'unverified'
          : cur == 'unverified' && verified
          ? 'active'
          : cur;
      return next == cur ? const {} : {'status': next};
    },
  );

  late final RecordSpec medication = RecordSpec(
    name: 'medication',
    collection: 'patient_medications',
    idField: 'medicationId',
    idPrefix: 'md_',
    viewPermission: ClinicPermission.medicationsView,
    managePermission: ClinicPermission.medicationsManage,
    listFilters: const {
      'status': ['current', 'completed', 'discontinued', 'unknown'],
    },
    fields: const {
      'name',
      'genericName',
      'strength',
      'dosage',
      'route',
      'frequency',
      'startDate',
      'endDate',
      'status',
      'prescriber',
      'notes',
      'source',
      'verify',
      'markReviewed',
    },
    parse: (r, {required partial}) {
      final start = _date(r, 'startDate', _clock);
      final end = _date(r, 'endDate', _clock);
      if (start != null && end != null && end.compareTo(start) < 0) {
        r.addIssue(
          'endDate',
          'invalid_period',
          'The end date cannot be before the start date.',
        );
      }
      return {
        'name': ?r.str('name', min: 2, max: 120),
        'genericName': ?r.str('genericName', max: 120, required: false),
        'strength': ?r.str('strength', max: 40, required: false),
        'dosage': ?r.str('dosage', max: 60, required: false),
        'route': ?r.str('route', max: 30, required: false),
        'frequency': ?r.str('frequency', max: 60, required: false),
        'startDate': ?start,
        'endDate': ?end,
        'status':
            r.enumOf<String>(
              'status',
              const ['current', 'completed', 'discontinued', 'unknown'],
              (v) => v,
              required: false,
            ) ??
            (partial ? null : 'unknown'),
        'prescriber': ?r.str('prescriber', max: 120, required: false),
        'notes': ?r.str('notes', max: 1000, required: false),
      }..removeWhere((k, v) => v == null);
    },
  );

  late final RecordSpec alert = RecordSpec(
    name: 'alert',
    collection: 'patient_alerts',
    idField: 'alertId',
    idPrefix: 'an_',
    viewPermission: ClinicPermission.alertsView,
    managePermission: ClinicPermission.alertsManage,
    immutable: const {'category'},
    listFilters: const {
      'category': alertCategories,
      'status': ['active', 'resolved'],
    },
    fields: const {
      'category',
      'title',
      'message',
      'priority',
      'status',
      'source',
      'verify',
      'markReviewed',
    },
    parse: (r, {required partial}) => {
      'category': ?r.enumOf<String>('category', alertCategories, (v) => v),
      'title': ?r.str('title', min: 2, max: 100),
      'message': ?r.str('message', min: 2, max: 500),
      'priority':
          r.enumOf<String>(
            'priority',
            const ['info', 'warning', 'critical'],
            (v) => v,
            required: false,
          ) ??
          (partial ? null : 'info'),
      'status':
          r.enumOf<String>(
            'status',
            const ['active', 'resolved'],
            (v) => v,
            required: false,
          ) ??
          (partial ? null : 'active'),
    }..removeWhere((k, v) => v == null),
  );
}

/// Generic create / update / list for the clinic-recorded record kinds.
class ClinicalRecordService {
  ClinicalRecordService(this._s);

  final PatientSupport _s;

  /// Alerts in clinical categories are only visible to, and editable by,
  /// roles with clinical access.
  bool _clinicalAlert(Object? category) =>
      clinicalAlertCategories.contains(category);

  void _requireAlertRights(TenantContext t, RecordSpec spec, Object? category) {
    if (spec.name == 'alert' &&
        _clinicalAlert(category) &&
        !(t.can(ClinicPermission.historyManage) ||
            t.can(ClinicPermission.allergiesManage))) {
      throw const ApiException.forbidden();
    }
  }

  Future<Paged> list(
    TenantContext t,
    RecordSpec spec,
    String patientId,
    Request req, {
    String? requestId,
  }) async {
    t.require(spec.viewPermission);
    final patient = await _s.load(t, patientId);
    final filters = <QueryFilter>[
      QueryFilter('patientId', FilterOp.eq, patientId),
    ];
    for (final e in spec.listFilters.entries) {
      final v = req.url.queryParameters[e.key];
      if (v == null || v.isEmpty) continue;
      if (!e.value.contains(v)) {
        throw ApiException.badRequest('${e.key} has an unsupported value.');
      }
      filters.add(QueryFilter(e.key, FilterOp.eq, v));
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, spec.collection),
        filters: filters,
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
    await _s.recordAccess(
      t,
      patient,
      '${spec.name}.listed',
      resourceType: spec.name,
      requestId: requestId,
    );
    if (spec.name != 'alert' || t.can(ClinicPermission.historyView)) {
      return page;
    }
    return Paged(
      page.docs.where((d) => !_clinicalAlert(d.data['category'])).toList(),
      page.meta,
    );
  }

  Map<String, Object?> _provenance(
    BodyReader r,
    TenantContext t, {
    required bool partial,
  }) {
    final source = r.enumOf<String>(
      'source',
      recordSources,
      (v) => v,
      required: false,
    );
    final verify = r.boolean('verify') ?? false;
    final review = r.boolean('markReviewed') ?? false;
    if (verify && t.role != ClinicRole.doctor) {
      r.addIssue(
        'verify',
        'not_allowed',
        'Only a doctor can mark information as clinician-verified.',
      );
    }
    return {'source': ?source, '_verify': verify, '_review': review || verify};
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    RecordSpec spec,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(spec.managePermission);
    final patient = await _s.load(t, patientId);
    _s.requireOpen(patient);
    final r = BodyReader(body)..rejectUnknown(spec.fields);
    final parsed = spec.parse(r, partial: false);
    final prov = _provenance(r, t, partial: false);
    r.throwIfInvalid();
    _requireAlertRights(t, spec, parsed['category']);

    final id = '${spec.idPrefix}${newId(length: 12)}';
    final now = _s.d.now;
    final verified = prov['_verify'] == true;
    var doc = <String, Object?>{
      spec.idField: id,
      'patientId': patientId,
      'tenantId': t.tenantId,
      'branchId': patient['branchId'],
      ...parsed,
      'source': verified
          ? 'clinician_verified'
          : (prov['source'] ?? 'clinic_recorded'),
      'verificationStatus': verified ? 'verified' : 'unverified',
      if (verified) ...{'verifiedBy': t.uid, 'verifiedAt': now},
      'recordedBy': t.uid,
      'recordedAt': now,
      'lastReviewedAt': prov['_review'] == true ? now : null,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
      'version': 1,
    };
    doc = {...doc, ...?spec.normalize?.call(doc)};
    await _s.d.store.transaction((tx) async {
      final cur = await _s.loadIn(tx, t, patientId);
      _s.requireOpen(cur);
      await _s.requireConsent(
        t,
        patientId,
        ConsentCatalog.dataProcessing,
        tx: tx,
      );
      tx.write([
        CreateOp(_s.d.path(t, spec.collection, id), doc),
        _s.auditOp(
          t,
          patientId,
          cur['branchId'] as String?,
          '${spec.name}.created',
          resourceType: spec.name,
          resourceId: id,
          after: {
            'source': doc['source'],
            'verification': doc['verificationStatus'],
            if (doc['category'] != null) 'category': doc['category'],
          },
          requestId: requestId,
        ),
      ]);
    });
    return present(doc);
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    RecordSpec spec,
    String patientId,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(spec.managePermission);
    final patient = await _s.load(t, patientId);
    _s.requireOpen(patient);
    final r = BodyReader(body, partial: true)..rejectUnknown(spec.fields);
    final parsed = spec.parse(r, partial: true);
    final prov = _provenance(r, t, partial: true);
    for (final k in spec.immutable) {
      if (body.containsKey(k)) {
        r.addIssue(k, 'immutable', '$k cannot be changed.');
      }
    }
    r.throwIfInvalid();
    if (parsed.isEmpty && prov['_verify'] != true && prov['_review'] != true) {
      throw const ApiException.badRequest('No fields to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, spec.collection, id);
      final cur = await tx.get(path);
      if (cur == null || cur['patientId'] != patientId) {
        throw const ApiException.notFound('Record not found.');
      }
      _requireAlertRights(t, spec, cur['category']);
      final changed = <String, Object?>{
        for (final e in parsed.entries)
          if (cur[e.key] != e.value) e.key: e.value,
      };
      final verify = prov['_verify'] == true;
      if (changed.isNotEmpty) {
        await _s.requireConsent(
          t,
          patientId,
          ConsentCatalog.dataProcessing,
          tx: tx,
        );
      }
      var patch = <String, Object?>{
        ...changed,
        if (prov['source'] != null) 'source': prov['source'],
        // changed content is no longer what a clinician verified
        if (changed.isNotEmpty && !verify) ...{
          'verificationStatus': 'unverified',
          'verifiedBy': null,
          'verifiedAt': null,
        },
        if (verify) ...{
          'verificationStatus': 'verified',
          'source': 'clinician_verified',
          'verifiedBy': t.uid,
          'verifiedAt': now,
        },
        if (prov['_review'] == true) 'lastReviewedAt': now,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
      };
      patch = {
        ...patch,
        ...?spec.normalize?.call({...cur, ...patch}),
      };
      tx.write([
        UpdateOp(path, patch),
        _s.revisionOp(t, patientId, spec.name, id, {
          for (final k in patch.keys) k: cur[k],
        }),
        _s.auditOp(
          t,
          patientId,
          patient['branchId'] as String?,
          '${spec.name}.updated',
          resourceType: spec.name,
          resourceId: id,
          before: {
            if (changed.containsKey('status')) 'status': cur['status'],
            'verification': cur['verificationStatus'],
          },
          after: {
            'fields': changed.keys.toList(),
            'verification':
                patch['verificationStatus'] ?? cur['verificationStatus'],
          },
          requestId: requestId,
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  // ------------------------------------------------------ emergency contacts

  Future<Map<String, Object?>> getContacts(
    TenantContext t,
    String patientId,
  ) async {
    t.require(ClinicPermission.patientsView);
    await _s.load(t, patientId);
    final doc = await _s.d.store.get(
      _s.d.path(t, 'patient_emergency_contacts', patientId),
    );
    return {
      'contacts': doc?['contacts'] ?? const <Object?>[],
      'updatedAt': jsonSafe(doc?['updatedAt']),
    };
  }

  Future<Map<String, Object?>> putContacts(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsUpdate);
    final patient = await _s.load(t, patientId);
    _s.requireOpen(patient);
    final r = BodyReader(body)..rejectUnknown({'contacts'});
    final contacts = EmergencyContacts.parse(r, 'contacts');
    r.throwIfInvalid();
    final path = _s.d.path(t, 'patient_emergency_contacts', patientId);
    final now = _s.d.now;
    await _s.d.store.transaction((tx) async {
      final cur = await tx.get(path);
      tx.write([
        if (cur == null)
          CreateOp(path, {
            'patientId': patientId,
            'tenantId': t.tenantId,
            'contacts': contacts,
            'updatedAt': now,
            'updatedBy': t.uid,
          })
        else ...[
          UpdateOp(path, {
            'contacts': contacts,
            'updatedAt': now,
            'updatedBy': t.uid,
          }),
          _s.revisionOp(t, patientId, 'emergency_contacts', patientId, cur),
        ],
        _s.auditOp(
          t,
          patientId,
          patient['branchId'] as String?,
          'emergency_contacts.replaced',
          resourceType: 'emergency_contacts',
          after: {'count': contacts!.length},
          requestId: requestId,
        ),
      ]);
    });
    return {'contacts': contacts, 'updatedAt': now.toUtc().toIso8601String()};
  }

  static Map<String, Object?> present(Map<String, Object?> d) =>
      jsonSafe(d)! as Map<String, Object?>;
}
