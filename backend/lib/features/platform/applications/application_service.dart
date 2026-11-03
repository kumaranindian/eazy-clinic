import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../audit/audit_service.dart';
import '../common/body_reader.dart';
import '../common/paging.dart';

const List<String> clinicTypes = [
  'general_medicine',
  'paediatrics',
  'dentistry',
  'dermatology',
  'gynaecology',
  'physiotherapy',
  'multi_specialty',
  'other',
];

/// Validated application sections.
class ApplicationInput {
  const ApplicationInput({
    required this.clinic,
    required this.address,
    required this.owner,
    required this.expectations,
    this.preferredPlanId,
  });

  final Map<String, Object?> clinic;
  final Map<String, Object?> address;
  final Map<String, Object?> owner;
  final Map<String, Object?> expectations;
  final String? preferredPlanId;

  static const Set<String> fields = {
    'clinic',
    'address',
    'owner',
    'expectations',
    'preferredPlanId',
  };

  /// [partial] is used when an applicant answers an information request and
  /// may correct individual sections or fields.
  static ApplicationInput parse(
    Map<String, Object?> body, {
    required bool partial,
  }) {
    final r = BodyReader(body, partial: partial)..rejectUnknown(fields);
    final clinic = r.object('clinic');
    final address = r.object('address');
    final owner = r.object('owner');
    final exp = r.object('expectations');
    final plan = r.str('preferredPlanId', min: 5, max: 40, required: false);

    final out = ApplicationInput(
      clinic: {},
      address: {},
      owner: {},
      expectations: {},
      preferredPlanId: plan,
    );
    if (clinic != null) {
      clinic.rejectUnknown({
        'name',
        'type',
        'registrationNumber',
        'email',
        'phone',
        'website',
        'description',
      });
      final type = clinic.str('type', max: 40);
      if (type != null && !clinicTypes.contains(type)) {
        clinic.addIssue(
          'type',
          'invalid_value',
          'type must be one of: ${clinicTypes.join(', ')}.',
        );
      }
      final website = clinic.str('website', max: 200, required: false);
      if (website != null) {
        final uri = Uri.tryParse(website);
        if (uri == null ||
            !(uri.scheme == 'http' || uri.scheme == 'https') ||
            uri.host.isEmpty) {
          clinic.addIssue(
            'website',
            'invalid_url',
            'website must be an http(s) URL.',
          );
        }
      }
      _put(out.clinic, {
        'name': clinic.str('name', min: 2, max: 120),
        'type': type,
        'registrationNumber': clinic.str(
          'registrationNumber',
          max: 50,
          required: false,
        ),
        'email': clinic.email('email'),
        'phone': clinic.phone('phone'),
        'website': website,
        'description': clinic.str(
          'description',
          min: 0,
          max: 1000,
          required: false,
        ),
      });
    }
    if (address != null) {
      address.rejectUnknown({
        'line1',
        'line2',
        'city',
        'state',
        'country',
        'postalCode',
      });
      final country = address.str('country', min: 2, max: 60);
      final postal = address.str('postalCode', min: 3, max: 10);
      if (postal != null &&
          (country ?? 'India').toLowerCase() == 'india' &&
          !RegExp(r'^[1-9][0-9]{5}$').hasMatch(postal)) {
        address.addIssue(
          'postalCode',
          'invalid_postal_code',
          'Enter a valid 6-digit PIN code.',
        );
      }
      _put(out.address, {
        'line1': address.str('line1', min: 3, max: 120),
        'line2': address.str('line2', max: 120, required: false),
        'city': address.str('city', min: 2, max: 60),
        'state': address.str('state', min: 2, max: 60),
        'country': country,
        'postalCode': postal,
      });
    }
    if (owner != null) {
      owner.rejectUnknown({'fullName', 'email', 'phone', 'designation'});
      _put(out.owner, {
        'fullName': owner.str('fullName', min: 2, max: 80),
        'email': owner.email('email'),
        'phone': owner.phone('phone'),
        'designation': owner.str('designation', max: 80, required: false),
      });
    }
    if (exp != null) {
      exp.rejectUnknown({'doctors', 'staff', 'monthlyPatients'});
      _put(out.expectations, {
        'doctors': exp.integer('doctors', min: 0, max: 1000),
        'staff': exp.integer('staff', min: 0, max: 5000),
        'monthlyPatients': exp.integer('monthlyPatients', min: 0, max: 1000000),
      });
    }
    r.throwIfInvalid();
    return out;
  }

  static void _put(Map<String, Object?> target, Map<String, Object?> values) {
    values.forEach((k, v) {
      if (v != null) target[k] = v;
    });
  }
}

/// Clinic registration applications: submission, applicant follow-up and
/// platform review. Approval (and tenant creation) lives in `TenantService`.
class ApplicationService {
  ApplicationService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String collection = 'clinic_applications';
  static const Duration rejectionCooldown = Duration(days: 7);
  static const List<String> openStatuses = [
    'submitted',
    'under_review',
    'additional_information_required',
  ];

  DateTime get _now => _clock().toUtc();

  static ApplicationStatus statusOf(Map<String, Object?> app) =>
      ApplicationStatus.tryParse(app['status'] as String?) ??
      ApplicationStatus.rejected;

  /// Duplicate-detection key: same clinic name in the same city and PIN.
  static String dupKey(
    Map<String, Object?> clinic,
    Map<String, Object?> address,
  ) {
    String norm(Object? v) =>
        '$v'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '${norm(clinic['name'])}|${norm(address['city'])}|${norm(address['postalCode'])}';
  }

  CreateOp historyOp(
    String id,
    Actor actor, {
    ApplicationStatus? from,
    required ApplicationStatus to,
    String? reason,
  }) => CreateOp('$collection/$id/history/${newId()}', {
    'fromStatus': from?.wireName,
    'toStatus': to.wireName,
    'actorUid': actor.uid,
    'actorRole': actor.role,
    'reason': reason,
    'at': _now,
  });

  // --------------------------------------------------------------- applicant

  Future<Map<String, Object?>> submit({
    required String applicantUid,
    required String applicantEmail,
    required ApplicationInput input,
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final mine = await tx.query(
        DocQuery(
          collection,
          filters: [
            QueryFilter('applicantUid', FilterOp.eq, applicantUid),
            const QueryFilter('status', FilterOp.inList, openStatuses),
          ],
          limit: 1,
        ),
      );
      if (mine.isNotEmpty) {
        throw const ApiException.conflict(
          'You already have an application in progress.',
        );
      }
      final rejected = await tx.query(
        DocQuery(
          collection,
          filters: [
            QueryFilter('applicantUid', FilterOp.eq, applicantUid),
            const QueryFilter('status', FilterOp.eq, 'rejected'),
          ],
          orderBy: const OrderBy('decidedAt', descending: true),
          limit: 1,
        ),
      );
      final now = _now;
      if (rejected.isNotEmpty) {
        final decided = rejected.first.data['decidedAt'] as DateTime?;
        if (decided != null && now.isBefore(decided.add(rejectionCooldown))) {
          throw ApiException.conflict(
            'A previous application was rejected. You can submit a new one after '
            '${decided.add(rejectionCooldown).toIso8601String().substring(0, 10)}.',
          );
        }
      }
      final key = dupKey(input.clinic, input.address);
      final dup = await tx.query(
        DocQuery(
          collection,
          filters: [
            QueryFilter('dupKey', FilterOp.eq, key),
            const QueryFilter('status', FilterOp.inList, [
              ...openStatuses,
              'approved',
            ]),
          ],
          limit: 1,
        ),
      );
      if (dup.isNotEmpty) {
        throw const ApiException.conflict(
          'An application for this clinic already exists. Contact EazyClinic support if you believe this is a mistake.',
        );
      }
      final planId = input.preferredPlanId;
      if (planId != null) {
        final plan = await tx.get('subscription_plans/$planId');
        if (plan == null || plan['status'] != PlanStatus.active.wireName) {
          throw ApiException.validation([
            const FieldIssue(
              field: 'preferredPlanId',
              code: 'invalid_plan',
              message: 'That plan is not available.',
            ),
          ]);
        }
      }
      final id = 'app_${newId(length: 16)}';
      final doc = <String, Object?>{
        'applicationId': id,
        'applicantUid': applicantUid,
        'applicantEmail': applicantEmail,
        'status': ApplicationStatus.submitted.wireName,
        'clinic': input.clinic,
        'address': input.address,
        'owner': input.owner,
        'expectations': input.expectations,
        'preferredPlanId': planId,
        'clinicNameLower': '${input.clinic['name']}'.toLowerCase(),
        'dupKey': key,
        'submittedAt': now,
        'createdAt': now,
        'updatedAt': now,
        'decidedAt': null,
        'decisionReason': null,
        'infoRequest': null,
        'infoResponses': <Object?>[],
        'tenantId': null,
      };
      final actor = Actor(applicantUid, 'applicant');
      tx.write([
        CreateOp('$collection/$id', doc),
        historyOp(id, actor, to: ApplicationStatus.submitted),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'application.submitted',
            targetType: 'clinic_application',
            targetId: id,
            requestId: requestId,
            after: {'status': 'submitted'},
          ),
        ),
      ]);
      return doc;
    });
  }

  Future<Paged> listMine(String uid, Request request) => runPaged(
    _store,
    DocQuery(
      collection,
      filters: [QueryFilter('applicantUid', FilterOp.eq, uid)],
      orderBy: const OrderBy('submittedAt', descending: true),
    ),
    request,
  );

  /// Applicant's own application. Anyone else gets 404 (existence not leaked).
  Future<Map<String, Object?>> getMine(String id, String uid) async {
    final app = await _store.get('$collection/$id');
    if (app == null || app['applicantUid'] != uid) {
      throw const ApiException.notFound('Application not found.');
    }
    final history = await _history(id);
    return presentForApplicant(app, history);
  }

  Future<Map<String, Object?>> respond({
    required String id,
    required String uid,
    required String message,
    required ApplicationInput updates,
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final app = await tx.get('$collection/$id');
      if (app == null || app['applicantUid'] != uid) {
        throw const ApiException.notFound('Application not found.');
      }
      final from = statusOf(app);
      if (from != ApplicationStatus.additionalInformationRequired) {
        throw const ApiException.conflict(
          'No information has been requested for this application.',
        );
      }
      final now = _now;
      Map<String, Object?> merge(String k, Map<String, Object?> add) => {
        ...(app[k]! as Map).cast<String, Object?>(),
        ...add,
      };
      final clinic = merge('clinic', updates.clinic);
      final address = merge('address', updates.address);
      final patch = <String, Object?>{
        'status': ApplicationStatus.submitted.wireName,
        'clinic': clinic,
        'address': address,
        'owner': merge('owner', updates.owner),
        'expectations': merge('expectations', updates.expectations),
        'clinicNameLower': '${clinic['name']}'.toLowerCase(),
        'dupKey': dupKey(clinic, address),
        'infoResponses': [
          ...((app['infoResponses'] as List?) ?? const []),
          {'message': message, 'respondedAt': now},
        ],
        'updatedAt': now,
      };
      final actor = Actor(uid, 'applicant');
      tx.write([
        UpdateOp('$collection/$id', patch),
        historyOp(
          id,
          actor,
          from: from,
          to: ApplicationStatus.submitted,
          reason: 'information_provided',
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'application.information_provided',
            targetType: 'clinic_application',
            targetId: id,
            requestId: requestId,
            before: {'status': from.wireName},
            after: {'status': 'submitted'},
          ),
        ),
      ]);
      return presentForApplicant({...app, ...patch}, await _history(id));
    });
  }

  Future<Map<String, Object?>> withdraw(
    String id,
    String uid, {
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final app = await tx.get('$collection/$id');
      if (app == null || app['applicantUid'] != uid) {
        throw const ApiException.notFound('Application not found.');
      }
      final from = statusOf(app);
      if (!from.canTransitionTo(ApplicationStatus.withdrawn)) {
        throw ApiException.conflict(
          'A ${from.wireName} application cannot be withdrawn.',
        );
      }
      final now = _now;
      final patch = {'status': 'withdrawn', 'updatedAt': now, 'decidedAt': now};
      final actor = Actor(uid, 'applicant');
      tx.write([
        UpdateOp('$collection/$id', patch),
        historyOp(id, actor, from: from, to: ApplicationStatus.withdrawn),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'application.withdrawn',
            targetType: 'clinic_application',
            targetId: id,
            requestId: requestId,
            before: {'status': from.wireName},
            after: {'status': 'withdrawn'},
          ),
        ),
      ]);
      return presentForApplicant({...app, ...patch}, const []);
    });
  }

  // --------------------------------------------------------------- platform

  Future<Paged> list(
    Request request, {
    ApplicationStatus? status,
    String? q,
  }) async {
    final raw = q?.trim();
    final query = raw?.toLowerCase();
    if (raw != null && raw.startsWith('app_')) {
      // Search by id: exact, case-sensitive lookup.
      final app = await _store.get('$collection/$raw');
      final docs = app == null || (status != null && statusOf(app) != status)
          ? <StoredDoc>[]
          : [StoredDoc('$collection/$raw', app)];
      return Paged(docs, const PageMeta(limit: 1, hasMore: false));
    }
    if (query != null && query.isNotEmpty) {
      return runPaged(
        _store,
        DocQuery(
          collection,
          filters: [
            if (status != null)
              QueryFilter('status', FilterOp.eq, status.wireName),
            QueryFilter('clinicNameLower', FilterOp.gte, query),
            QueryFilter('clinicNameLower', FilterOp.lt, '$query'),
          ],
          orderBy: const OrderBy('clinicNameLower'),
        ),
        request,
      );
    }
    return runPaged(
      _store,
      DocQuery(
        collection,
        filters: [
          if (status != null)
            QueryFilter('status', FilterOp.eq, status.wireName),
        ],
        orderBy: const OrderBy('submittedAt', descending: true),
      ),
      request,
    );
  }

  Future<Map<String, Object?>> detail(String id) async {
    final app = await _store.get('$collection/$id');
    if (app == null) {
      throw const ApiException.notFound('Application not found.');
    }
    final notes = await _store.query(
      DocQuery(
        '$collection/$id/internal_notes',
        orderBy: const OrderBy('at', descending: true),
        limit: 100,
      ),
    );
    return {
      ...presentForPlatform(app),
      'history': (await _history(id))
          .map(
            (h) => {'id': h.id, ...jsonSafe(h.data)! as Map<String, Object?>},
          )
          .toList(),
      'internalNotes': notes
          .map(
            (n) => {'id': n.id, ...jsonSafe(n.data)! as Map<String, Object?>},
          )
          .toList(),
    };
  }

  Future<Map<String, Object?>> _review(
    String id,
    Actor actor, {
    required ApplicationStatus to,
    String? reason,
    String? requestId,
    required String action,
    Map<String, Object?> Function(DateTime now)? extra,
  }) {
    return _store.transaction((tx) async {
      final app = await tx.get('$collection/$id');
      if (app == null) {
        throw const ApiException.notFound('Application not found.');
      }
      final from = statusOf(app);
      if (!from.canTransitionTo(to)) {
        throw ApiException.conflict(
          'A ${from.wireName} application cannot become ${to.wireName}.',
        );
      }
      final now = _now;
      final patch = {
        'status': to.wireName,
        'updatedAt': now,
        'reviewedBy': actor.uid,
        'reviewedAt': now,
        ...?extra?.call(now),
      };
      tx.write([
        UpdateOp('$collection/$id', patch),
        historyOp(id, actor, from: from, to: to, reason: reason),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: action,
            targetType: 'clinic_application',
            targetId: id,
            reason: reason,
            requestId: requestId,
            before: {'status': from.wireName},
            after: {'status': to.wireName},
          ),
        ),
      ]);
      return presentForPlatform({...app, ...patch});
    });
  }

  Future<Map<String, Object?>> startReview(
    String id,
    Actor actor, {
    String? requestId,
  }) => _review(
    id,
    actor,
    to: ApplicationStatus.underReview,
    action: 'application.review_started',
    requestId: requestId,
  );

  Future<Map<String, Object?>> requestInformation(
    String id,
    String message,
    Actor actor, {
    String? requestId,
  }) => _review(
    id,
    actor,
    to: ApplicationStatus.additionalInformationRequired,
    reason: message,
    action: 'application.information_requested',
    requestId: requestId,
    extra: (now) => {
      'infoRequest': {'message': message, 'requestedAt': now},
    },
  );

  Future<Map<String, Object?>> reject(
    String id,
    String reason,
    Actor actor, {
    String? requestId,
  }) => _review(
    id,
    actor,
    to: ApplicationStatus.rejected,
    reason: reason,
    action: 'application.rejected',
    requestId: requestId,
    extra: (now) => {'decidedAt': now, 'decisionReason': reason},
  );

  Future<void> addNote(
    String id,
    String note,
    Actor actor, {
    String? requestId,
  }) async {
    final app = await _store.get('$collection/$id');
    if (app == null) {
      throw const ApiException.notFound('Application not found.');
    }
    await _store.commit([
      CreateOp('$collection/$id/internal_notes/${newId()}', {
        'note': note,
        'authorUid': actor.uid,
        'at': _now,
      }),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'application.note_added',
          targetType: 'clinic_application',
          targetId: id,
          requestId: requestId,
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------ presenters

  Future<List<StoredDoc>> _history(String id) => _store.query(
    DocQuery(
      '$collection/$id/history',
      orderBy: const OrderBy('at'),
      limit: 100,
    ),
  );

  /// What the applicant may see: no internal notes, no reviewer identity.
  static Map<String, Object?> presentForApplicant(
    Map<String, Object?> app,
    List<StoredDoc> history,
  ) => {
    'applicationId': app['applicationId'],
    'status': app['status'],
    'clinic': app['clinic'],
    'address': app['address'],
    'owner': app['owner'],
    'expectations': app['expectations'],
    'preferredPlanId': app['preferredPlanId'],
    'submittedAt': jsonSafe(app['submittedAt']),
    'updatedAt': jsonSafe(app['updatedAt']),
    'decisionReason': app['decisionReason'],
    'infoRequest': jsonSafe(app['infoRequest']),
    'tenantId': app['tenantId'],
    'history': [
      for (final h in history)
        {
          'status': h.data['toStatus'],
          'at': jsonSafe(h.data['at']),
          'by': h.data['actorRole'] == 'applicant' ? 'you' : 'EazyClinic',
          'reason': h.data['actorRole'] == 'applicant'
              ? null
              : h.data['reason'],
        },
    ],
  };

  static Map<String, Object?> presentForPlatform(Map<String, Object?> app) {
    final copy = Map<String, Object?>.from(app)
      ..remove('dupKey')
      ..remove('clinicNameLower');
    return jsonSafe(copy)! as Map<String, Object?>;
  }
}
