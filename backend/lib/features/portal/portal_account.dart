import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../auth/domain/auth_context.dart';
import '../patients/consent_service.dart';
import '../platform/common/body_reader.dart';
import 'portal_notifier.dart';
import 'portal_support.dart';

String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

/// Devices, the in-app inbox and notification preferences.
///
/// Push delivery is Phase 10's job. This service only keeps *whose* devices
/// exist (scoped to the signed-in user, never writable for someone else) and
/// the inbox the app reads. Logging out deactivates the device.
class PortalNotificationService {
  PortalNotificationService(this._s);

  final PortalSupport _s;

  static final RegExp _deviceId = RegExp(r'^[A-Za-z0-9_\-]{8,64}$');

  /// Registers or refreshes an FCM token for the caller. A token belongs to one
  /// user at a time: registering it as another user moves it.
  Future<Map<String, Object?>> registerDevice(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final me = await _s.accounts.requireAccount(ctx);
    final r = BodyReader(body)
      ..rejectUnknown({'deviceId', 'token', 'platform', 'appVersion'});
    final deviceId = r.str('deviceId', min: 8, max: 64);
    if (deviceId != null && !_deviceId.hasMatch(deviceId)) {
      r.addIssue('deviceId', 'invalid_value', 'Use letters, digits, - or _.');
    }
    final token = r.str('token', min: 20, max: 4096);
    final platform = r.enumOf<String>('platform', const ['android'], (v) => v);
    final version = r.str('appVersion', max: 20, required: false);
    r.throwIfInvalid();
    final id = 'dev_${_hash(token!).substring(0, 32)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'deviceDocId': id,
      'uid': ctx.user.uid,
      'accountId': me['accountId'],
      'deviceId': deviceId,
      'tokenHash': _hash(token),
      // the token is needed to send; it is never returned by any API
      'token': token,
      'platform': platform,
      'appVersion': version,
      'active': true,
      'updatedAt': now,
    }..removeWhere((k, v) => v == null);
    await _s.store.transaction((tx) async {
      final existing = await tx.get('patient_devices/$id');
      tx.write([
        existing == null
            ? CreateOp('patient_devices/$id', {...doc, 'createdAt': now})
            : UpdateOp('patient_devices/$id', doc),
      ]);
    });
    return {'deviceId': deviceId, 'registered': true, 'platform': platform};
  }

  /// Deactivates the caller's tokens for [deviceId] (called on logout).
  Future<Map<String, Object?>> unregisterDevice(
    AuthContext ctx,
    String deviceId,
  ) async {
    if (!_deviceId.hasMatch(deviceId)) throw const ApiException.notFound();
    final rows = await _s.store.query(
      DocQuery(
        'patient_devices',
        filters: [
          QueryFilter('uid', FilterOp.eq, ctx.user.uid),
          QueryFilter('deviceId', FilterOp.eq, deviceId),
        ],
        limit: 10,
      ),
    );
    await _s.store.commit([
      for (final r in rows)
        UpdateOp('patient_devices/${r.id}', {
          'active': false,
          'updatedAt': _s.d.now,
        }),
    ]);
    return {'deviceId': deviceId, 'registered': false};
  }

  Future<Map<String, Object?>> inbox(AuthContext ctx) async {
    final me = await _s.accounts.requireAccount(ctx);
    final rows = await _s.store.query(
      DocQuery(
        'patient_notifications',
        filters: [QueryFilter('accountId', FilterOp.eq, me['accountId'])],
        orderBy: const OrderBy('createdAt', descending: true),
        limit: 50,
      ),
    );
    final items = [
      for (final r in rows)
        if (r.data['archived'] != true)
          PortalSupport.pick(r.data, [
            'notificationId',
            'category',
            'title',
            'body',
            'clinicId',
            'resourceType',
            'resourceId',
            'read',
            'createdAt',
          ]),
    ];
    return {
      'items': items,
      'unread': items.where((i) => i['read'] != true).length,
    };
  }

  /// Marks every unread entry of the caller as read (up to 200 at a time).
  Future<Map<String, Object?>> markAllRead(AuthContext ctx) async {
    final me = await _s.accounts.requireAccount(ctx);
    final rows = await _s.store.query(
      DocQuery(
        'patient_notifications',
        filters: [
          QueryFilter('accountId', FilterOp.eq, me['accountId']),
          const QueryFilter('read', FilterOp.eq, false),
        ],
        limit: 200,
      ),
    );
    if (rows.isNotEmpty) {
      await _s.store.commit([
        for (final r in rows)
          UpdateOp(r.path, {'read': true, 'readAt': _s.d.now}),
      ]);
    }
    return {'marked': rows.length, 'more': rows.length >= 200};
  }

  /// Removes an entry from the inbox (kept for the audit trail, not shown).
  Future<Map<String, Object?>> archive(AuthContext ctx, String id) async {
    final me = await _s.accounts.requireAccount(ctx);
    final n = await _s.store.get('patient_notifications/$id');
    if (n == null || n['accountId'] != me['accountId']) {
      throw const ApiException.notFound('Notification not found.');
    }
    await _s.store.commit([
      UpdateOp('patient_notifications/$id', {
        'archived': true,
        'read': true,
        'archivedAt': _s.d.now,
      }),
    ]);
    return {'notificationId': id, 'archived': true};
  }

  Future<Map<String, Object?>> markRead(AuthContext ctx, String id) async {
    final me = await _s.accounts.requireAccount(ctx);
    final n = await _s.store.get('patient_notifications/$id');
    if (n == null || n['accountId'] != me['accountId']) {
      throw const ApiException.notFound('Notification not found.');
    }
    if (n['read'] != true) {
      await _s.store.commit([
        UpdateOp('patient_notifications/$id', {
          'read': true,
          'readAt': _s.d.now,
        }),
      ]);
    }
    return {'notificationId': id, 'read': true};
  }

  Future<Map<String, Object?>> preferences(AuthContext ctx) async {
    final me = await _s.accounts.requireAccount(ctx);
    final p = await _s.store.get(
      'patient_notification_preferences/${me['accountId']}',
    );
    final saved =
        (p?['categories'] as Map?)?.cast<String, Object?>() ?? const {};
    return {
      'pushEnabled': p?['pushEnabled'] != false,
      'categories': {
        for (final c in notificationCategories) c: saved[c] != false,
      },
    };
  }

  Future<Map<String, Object?>> setPreferences(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final me = await _s.accounts.requireAccount(ctx);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'pushEnabled', 'categories'});
    final push = r.boolean('pushEnabled');
    Map<String, Object?>? cats;
    if (r.has('categories')) {
      final raw = r.body['categories'];
      if (raw is! Map ||
          raw.entries.any(
            (e) => !notificationCategories.contains(e.key) || e.value is! bool,
          )) {
        r.addIssue(
          'categories',
          'invalid_value',
          'Give known categories with true or false.',
        );
      } else {
        cats = raw.cast<String, Object?>();
      }
    }
    r.throwIfInvalid();
    final path = 'patient_notification_preferences/${me['accountId']}';
    final cur = await _s.store.get(path);
    final merged = {
      ...((cur?['categories'] as Map?)?.cast<String, Object?>() ?? const {}),
      ...?cats,
    };
    final doc = {
      'accountId': me['accountId'],
      'pushEnabled': push ?? cur?['pushEnabled'] ?? true,
      'categories': merged,
      'updatedAt': _s.d.now,
    };
    await _s.store.commit([
      cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
    ]);
    return preferences(ctx);
  }
}

/// The patient's own profile, consent decisions and deletion request.
class PortalAccountService {
  PortalAccountService(this._s, this._consents);

  final PortalSupport _s;
  final ConsentService _consents;

  static const Set<String> _languages = {
    'en',
    'hi',
    'mr',
    'ta',
    'te',
    'bn',
    'gu',
    'kn',
    'ml',
    'pa',
  };

  Future<Map<String, Object?>> profile(AuthContext ctx) async {
    final me = await _s.accounts.requireAccount(ctx);
    final out = _s.accounts.present(me, ctx);
    final missing = <String>[
      if ('${me['displayName'] ?? ''}'.isEmpty) 'name',
      if ('${me['phone'] ?? ''}'.isEmpty) 'phone',
      if (me['dateOfBirth'] == null) 'dateOfBirth',
      if (me['address'] == null) 'address',
      if (me['emergencyContact'] == null) 'emergencyContact',
    ];
    final deletion = await _s.store.get(
      'account_deletion_requests/${me['accountId']}',
    );
    return {
      ...out,
      'profileCompletion': ((5 - missing.length) * 100) ~/ 5,
      'profileMissing': missing,
      'linkedClinics': [
        for (final l in await _s.links(
          await _s.subject(ctx, null, PortalSupport.scopeRecords),
        ))
          {'clinicId': l.tenantId, 'clinicName': l.clinicName, 'mrn': l.mrn},
      ],
      if (deletion != null)
        'deletionRequest': PortalSupport.pick(deletion, [
          'status',
          'requestedAt',
        ]),
    };
  }

  /// Only low-risk fields can be edited here. Name, date of birth, phone and
  /// e-mail changes need verification and are not offered (TD-66); clinic
  /// records are never changed by a profile edit.
  Future<Map<String, Object?>> updateProfile(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final me = await _s.accounts.requireAccount(ctx);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'preferredLanguage', 'address', 'emergencyContact'});
    final patch = <String, Object?>{};
    if (r.has('preferredLanguage')) {
      final v = r.body['preferredLanguage'];
      if (v is! String || !_languages.contains(v)) {
        r.addIssue(
          'preferredLanguage',
          'invalid_value',
          'Choose a supported language.',
        );
      } else {
        patch['preferredLanguage'] = v;
      }
    }
    final addr = r.object('address', required: false);
    if (addr != null) {
      addr.rejectUnknown({'line1', 'line2', 'city', 'state', 'postalCode'});
      patch['address'] = {
        'line1': addr.str('line1', min: 3, max: 120),
        'line2': addr.str('line2', max: 120, required: false),
        'city': addr.str('city', max: 60),
        'state': addr.str('state', max: 60, required: false),
        'postalCode': addr.str('postalCode', min: 4, max: 10),
      }..removeWhere((k, v) => v == null);
      for (final x in addr.issues) {
        r.addIssue('address.${x.field}', x.code, x.message);
      }
    }
    final ec = r.object('emergencyContact', required: false);
    if (ec != null) {
      ec.rejectUnknown({'name', 'phone', 'relationship'});
      patch['emergencyContact'] = {
        'name': ec.str('name', min: 2, max: 100),
        'phone': ec.phone('phone'),
        'relationship': ec.str('relationship', max: 40, required: false),
      }..removeWhere((k, v) => v == null);
      for (final x in ec.issues) {
        r.addIssue('emergencyContact.${x.field}', x.code, x.message);
      }
    }
    r.throwIfInvalid();
    if (patch.isEmpty) return profile(ctx);
    patch['updatedAt'] = _s.d.now;
    await _s.store.commit([
      UpdateOp('patient_accounts/${me['accountId']}', patch),
    ]);
    return profile(ctx);
  }

  /// A request only: nothing is deleted. Clinic records are retained as the
  /// clinics' records and the account's deletion is decided by the platform
  /// under the retention rules (TD-66).
  Future<Map<String, Object?>> requestDeletion(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final me = await _s.accounts.requireAccount(ctx);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', max: 300, required: false);
    r.throwIfInvalid();
    final path = 'account_deletion_requests/${me['accountId']}';
    final cur = await _s.store.get(path);
    if (cur != null && cur['status'] == 'pending') {
      return {
        ...PortalSupport.pick(cur, ['status', 'requestedAt']),
        'idempotentReplay': true,
      };
    }
    final doc = {
      'accountId': me['accountId'],
      'uid': ctx.user.uid,
      'status': 'pending',
      'reason': reason,
      'requestedAt': _s.d.now,
      'note':
          'Your request was received. Clinic medical records are kept by each clinic as required by law.',
    }..removeWhere((k, v) => v == null);
    await _s.store.commit([
      cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
    ]);
    return PortalSupport.pick(doc, ['status', 'requestedAt', 'note']);
  }

  /// People the caller is related to, for the app's person switcher and the
  /// family screen. Only the other person's display name and kind are shown.
  Future<List<Map<String, Object?>>> family(AuthContext ctx) async {
    final me = await _s.accounts.requireAccount(ctx);
    final mine = me['accountId']! as String;
    final out = <Map<String, Object?>>[];
    for (final rel in await _s.accounts.listMine(ctx)) {
      final iRequested = rel['requesterAccountId'] == mine;
      final otherId =
          '${iRequested ? rel['subjectAccountId'] : rel['requesterAccountId']}';
      final other = await _s.store.get('patient_accounts/$otherId');
      final active =
          rel['status'] == 'active' && rel['verificationStatus'] == 'verified';
      out.add({
        ...PortalSupport.pick(rel, [
          'relationshipId',
          'relationshipType',
          'isGuardian',
          'permissionScope',
          'status',
          'verificationStatus',
          'validUntil',
        ]),
        'direction': iRequested ? 'i_manage' : 'manages_me',
        'otherAccountId': otherId,
        'otherName': other?['displayName'],
        'otherKind': other?['kind'],
        // the app may act for this person only while the relationship is live
        'canActFor': iRequested && active,
      });
    }
    return out;
  }

  // ------------------------------------------------------------ consent

  Map<String, Object?> catalog() => {
    'version': ConsentCatalog.version,
    'purposes': [
      for (final p in ConsentCatalog.purposes)
        {'type': p.type, 'purpose': p.purpose, 'text': p.text},
    ],
  };

  Future<ClinicLink> _ownLink(AuthContext ctx, String clinicId) async {
    final s = await _s.subject(ctx, null, PortalSupport.scopeConsent);
    return _s.requireLink(s, clinicId);
  }

  Future<List<Map<String, Object?>>> consents(
    AuthContext ctx,
    String clinicId,
  ) async {
    final link = await _ownLink(ctx, clinicId);
    final rows = await _s.store.query(
      DocQuery(
        _s.path(clinicId, 'patient_consents'),
        filters: [QueryFilter('patientId', FilterOp.eq, link.patientId)],
        limit: 100,
      ),
    );
    final out = [
      for (final r in rows)
        PortalSupport.pick(r.data, [
          'consentId',
          'type',
          'purpose',
          'textVersion',
          'status',
          'createdAt',
          'revokedAt',
          'expiresAt',
        ]),
    ]..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return out;
  }

  /// Records the caller's own decision for one purpose at one clinic. Consent
  /// for a dependent is given by the guardian through the clinic.
  Future<Map<String, Object?>> decide(
    AuthContext ctx,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({'clinicId', 'type', 'decision', 'textVersion'});
    final clinicId = r.str('clinicId', max: 80);
    final type = r.str('type', max: 40);
    final decision = r.str('decision', max: 10);
    final version = r.str('textVersion', max: 10);
    r.throwIfInvalid();
    final link = await _ownLink(ctx, clinicId!);
    final t = await _s.actingIn(ctx, clinicId, write: true);
    final res = await _consents.record(t, link.patientId, {
      'type': type,
      'decision': decision,
      'textVersion': version,
      'grantedBy': {'type': 'patient'},
      'collectionMethod': 'digital_form',
    }, requestId: requestId);
    return PortalSupport.pick(res, [
      'consentId',
      'type',
      'status',
      'textVersion',
      'createdAt',
    ]);
  }

  Future<Map<String, Object?>> withdraw(
    AuthContext ctx,
    String clinicId,
    String consentId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final link = await _ownLink(ctx, clinicId);
    final t = await _s.actingIn(ctx, clinicId, write: true);
    final c = await _s.store.get(
      _s.path(clinicId, 'patient_consents', consentId),
    );
    if (c == null || c['patientId'] != link.patientId) {
      throw const ApiException.notFound('Consent not found.');
    }
    final res = await _consents.revoke(t, link.patientId, consentId, {
      'reason': (body['reason'] as String?) ?? 'Withdrawn by the patient',
    }, requestId: requestId);
    return PortalSupport.pick(res, [
      'consentId',
      'type',
      'status',
      'revokedAt',
    ]);
  }
}
