import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../portal/portal_notifier.dart';
import 'notification_core.dart';
import 'notification_hub.dart';

const List<String> allNotificationCategories = [
  ...notificationCategories,
  'lab_sample_rejected',
  'security_event',
];

FieldIssue _issue(String f, String c, String m) =>
    FieldIssue(field: f, code: c, message: m);

Map<String, Object?> _present(Map<String, Object?> doc) =>
    (_safe(doc)! as Map).cast<String, Object?>();

Object? _safe(Object? v) {
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is Map) return {for (final e in v.entries) '${e.key}': _safe(e.value)};
  if (v is List) return v.map(_safe).toList();
  return v;
}

/// Staff notification center, preferences, devices and the administration of
/// templates, deliveries and channels of one clinic.
class NotificationService {
  NotificationService(this._d, this.hub, this._fcm, this._providers);

  final ClinicDeps _d;
  final NotificationHub hub;
  final FcmSender _fcm;
  final Map<String, MessageProvider> _providers;

  String _p(TenantContext t, String c, [String? id]) =>
      'tenants/${t.tenantId}/$c${id == null ? '' : '/$id'}';

  CreateOp _audit(
    TenantContext t,
    String action,
    String type,
    String id, {
    String? reason,
    String? requestId,
    Map<String, Object?>? after,
  }) => hub.audit(
    t.tenantId,
    actorUid: t.uid,
    actorRole: t.actorLabel,
    action: action,
    resourceType: type,
    resourceId: id,
    reason: reason,
    requestId: requestId,
    after: after,
  );

  // ---------------------------------------------------------------- inbox

  Future<Paged> inbox(TenantContext t, Request req, {bool? unreadOnly}) {
    return runPaged(
      _d.store,
      DocQuery(
        _p(t, 'notifications'),
        filters: [
          QueryFilter('recipientUid', FilterOp.eq, t.uid),
          const QueryFilter('archived', FilterOp.eq, false),
          if (unreadOnly == true) const QueryFilter('read', FilterOp.eq, false),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  Map<String, Object?> presentNotification(DocData n) => {
    ..._present(n)..removeWhere(
      (k, v) => k == 'recipientUid' || k == 'tenantId' || k == 'archived',
    ),
  };

  Future<Map<String, Object?>> unreadCount(TenantContext t) async {
    final rows = await _d.store.query(
      DocQuery(
        _p(t, 'notifications'),
        filters: [
          QueryFilter('recipientUid', FilterOp.eq, t.uid),
          const QueryFilter('read', FilterOp.eq, false),
          const QueryFilter('archived', FilterOp.eq, false),
        ],
        limit: 100,
      ),
    );
    return {'unread': rows.length, 'capped': rows.length >= 100};
  }

  Future<DocData> _own(TenantContext t, String id) async {
    final n = await _d.store.get(_p(t, 'notifications', id));
    if (n == null || n['recipientUid'] != t.uid) {
      throw const ApiException.notFound('Notification not found.');
    }
    return n;
  }

  Future<Map<String, Object?>> markRead(TenantContext t, String id) async {
    final n = await _own(t, id);
    if (n['read'] != true) {
      await _d.store.commit([
        UpdateOp(_p(t, 'notifications', id), {'read': true, 'readAt': _d.now}),
      ]);
    }
    return {'notificationId': id, 'read': true};
  }

  Future<Map<String, Object?>> readAll(TenantContext t) async {
    final rows = await _d.store.query(
      DocQuery(
        _p(t, 'notifications'),
        filters: [
          QueryFilter('recipientUid', FilterOp.eq, t.uid),
          const QueryFilter('read', FilterOp.eq, false),
          const QueryFilter('archived', FilterOp.eq, false),
        ],
        limit: 200,
      ),
    );
    if (rows.isNotEmpty) {
      await _d.store.commit([
        for (final r in rows)
          UpdateOp(r.path, {'read': true, 'readAt': _d.now}),
      ]);
    }
    return {'marked': rows.length, 'more': rows.length >= 200};
  }

  Future<Map<String, Object?>> archive(TenantContext t, String id) async {
    await _own(t, id);
    await _d.store.commit([
      UpdateOp(_p(t, 'notifications', id), {
        'archived': true,
        'read': true,
        'archivedAt': _d.now,
      }),
    ]);
    return {'notificationId': id, 'archived': true};
  }

  // ---------------------------------------------------------- preferences

  Future<Map<String, Object?>> preferences(TenantContext t) async {
    final p = await _d.store.get(_p(t, 'notification_preferences', t.uid));
    final saved = (p?['categories'] as Map?)?.cast<String, Object?>() ?? {};
    final ch = (p?['channels'] as Map?)?.cast<String, Object?>() ?? {};
    return {
      'pushEnabled': p?['pushEnabled'] != false,
      'channels': {
        for (final c in notificationChannels)
          if (c != 'in_app' && c != 'push') c: ch[c] != false,
      },
      'categories': {
        for (final c in allNotificationCategories)
          c: promotionalCategories.contains(c)
              ? saved[c] == true
              : saved[c] != false,
      },
      'essentialCategories': essentialCategories.toList()..sort(),
    };
  }

  Future<Map<String, Object?>> setPreferences(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'pushEnabled', 'channels', 'categories'});
    final push = r.boolean('pushEnabled');
    Map<String, Object?>? cats;
    Map<String, Object?>? chans;
    if (r.has('categories')) {
      final raw = r.body['categories'];
      if (raw is! Map ||
          raw.entries.any(
            (e) =>
                !allNotificationCategories.contains(e.key) || e.value is! bool,
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
    if (r.has('channels')) {
      final raw = r.body['channels'];
      if (raw is! Map ||
          raw.entries.any(
            (e) =>
                !const ['email', 'sms', 'whatsapp'].contains(e.key) ||
                e.value is! bool,
          )) {
        r.addIssue(
          'channels',
          'invalid_value',
          'Give email, sms or whatsapp with true or false.',
        );
      } else {
        chans = raw.cast<String, Object?>();
      }
    }
    r.throwIfInvalid();
    final path = _p(t, 'notification_preferences', t.uid);
    final cur = await _d.store.get(path);
    final doc = {
      'uid': t.uid,
      'tenantId': t.tenantId,
      'pushEnabled': push ?? cur?['pushEnabled'] ?? true,
      'channels': {
        ...((cur?['channels'] as Map?)?.cast<String, Object?>() ?? {}),
        ...?chans,
      },
      'categories': {
        ...((cur?['categories'] as Map?)?.cast<String, Object?>() ?? {}),
        ...?cats,
      },
      'updatedAt': _d.now,
    };
    await _d.store.commit([
      cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
      _audit(
        t,
        'notification_preferences.updated',
        'preferences',
        t.uid,
        requestId: requestId,
      ),
    ]);
    return preferences(t);
  }

  // -------------------------------------------------------------- devices

  static final RegExp _deviceId = RegExp(r'^[A-Za-z0-9_\-]{8,64}$');

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  /// A device token always belongs to the authenticated caller: the owner is
  /// never taken from the request. Registering a token again refreshes it.
  Future<Map<String, Object?>> registerDevice(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({'deviceId', 'token', 'platform', 'appVersion'});
    final deviceId = r.str('deviceId', min: 8, max: 64);
    if (deviceId != null && !_deviceId.hasMatch(deviceId)) {
      r.addIssue('deviceId', 'invalid_value', 'Use letters, digits, - or _.');
    }
    final token = r.str('token', min: 20, max: 4096);
    final platform = r.enumOf<String>('platform', const [
      'android',
      'web',
    ], (v) => v);
    final version = r.str('appVersion', max: 20, required: false);
    r.throwIfInvalid();
    final id = 'dev_${_hash(token!).substring(0, 32)}';
    final path = 'notification_devices/$id';
    final now = _d.now;
    await _d.store.transaction((tx) async {
      final cur = await tx.get(path);
      final doc = <String, Object?>{
        'deviceDocId': id,
        'uid': t.uid,
        'tenantId': t.tenantId,
        'deviceId': deviceId,
        'tokenHash': _hash(token),
        // needed to send; no API ever returns it
        'token': token,
        'platform': platform,
        'appVersion': version,
        'active': true,
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      tx.write([
        cur == null
            ? CreateOp(path, {...doc, 'createdAt': now})
            : UpdateOp(path, doc),
        _audit(
          t,
          'notification_device.registered',
          'device',
          id,
          requestId: requestId,
        ),
      ]);
    });
    return {'id': id, 'deviceId': deviceId, 'registered': true};
  }

  Future<Map<String, Object?>> removeDevice(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    final d = await _d.store.get('notification_devices/$id');
    if (d == null || d['uid'] != t.uid) {
      throw const ApiException.notFound('Device not found.');
    }
    await _d.store.commit([
      UpdateOp('notification_devices/$id', {
        'active': false,
        'removedAt': _d.now,
      }),
      _audit(
        t,
        'notification_device.removed',
        'device',
        id,
        requestId: requestId,
      ),
    ]);
    return {'id': id, 'registered': false};
  }

  // ------------------------------------------------------------ templates

  static final RegExp _locale = RegExp(r'^[a-z]{2}$');

  List<FieldIssue> _checkText(String eventType, String? subject, String? body) {
    final allowed = variablesFor(eventType);
    final issues = <FieldIssue>[];
    for (final (f, v) in [('subject', subject), ('body', body)]) {
      if (v == null) continue;
      for (final name in placeholdersIn(v)) {
        if (!allowed.contains(name)) {
          issues.add(
            _issue(
              f,
              'variable_not_allowed',
              '{{$name}} is not allowed for $eventType. Allowed: ${allowed.join(', ')}.',
            ),
          );
        }
      }
      if (v.contains('{{') && placeholdersIn(v).isEmpty ||
          RegExp(r'\{\{[^}]*[^A-Za-z0-9_\s}][^}]*\}\}').hasMatch(v)) {
        issues.add(
          _issue(f, 'invalid_placeholder', 'Use only {{name}} placeholders.'),
        );
      }
    }
    return issues;
  }

  Future<List<Map<String, Object?>>> templates(TenantContext t) async {
    t.require(ClinicPermission.notificationsManage);
    final rows = await _d.store.query(
      DocQuery(_p(t, 'notification_templates'), limit: 200),
    );
    return [
      for (final b in builtinTemplates)
        {
          'templateId': 'builtin:${b.eventType}:${b.channel}',
          'builtin': true,
          'eventType': b.eventType,
          'channel': b.channel,
          'locale': b.locale,
          'subject': b.subject,
          'body': b.body,
          'version': b.version,
          'active': true,
          'allowedVariables': variablesFor(b.eventType).toList()..sort(),
        },
      for (final r in rows)
        {
          ..._present(r.data),
          'builtin': false,
          'allowedVariables': variablesFor('${r.data['eventType']}').toList()
            ..sort(),
        },
    ];
  }

  Future<Map<String, Object?>> createTemplate(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'name',
        'eventType',
        'channel',
        'locale',
        'subject',
        'body',
      });
    final name = r.str('name', min: 2, max: 80);
    final type = r.enumOf<String>(
      'eventType',
      allNotificationCategories,
      (v) => v,
    );
    final channel = r.enumOf<String>('channel', notificationChannels, (v) => v);
    final locale = r.str('locale', min: 2, max: 2);
    if (locale != null && !_locale.hasMatch(locale)) {
      r.addIssue('locale', 'invalid_value', 'Use a two-letter language code.');
    }
    final subject = r.str('subject', max: 150, required: false);
    final text = r.str('body', min: 3, max: 1000);
    r.throwIfInvalid();
    final issues = _checkText(type!, subject, text);
    if (issues.isNotEmpty) throw ApiException.validation(issues);
    final key = _hash('${t.tenantId}:$type:$channel:$locale').substring(0, 24);
    final id = 'tpl_$key';
    final now = _d.now;
    final doc = <String, Object?>{
      'templateId': id,
      'tenantId': t.tenantId,
      'name': name,
      'eventType': type,
      'channel': channel,
      'locale': locale,
      'subject': subject ?? '',
      'body': text,
      'version': 1,
      'active': true,
      'createdBy': t.uid,
      'createdAt': now,
      'updatedAt': now,
    };
    try {
      await _d.store.commit([
        CreateOp(_p(t, 'notification_templates', id), doc),
        _audit(
          t,
          'notification_template.created',
          'template',
          id,
          requestId: requestId,
        ),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'A template for this event, channel and language already exists. Edit it instead.',
      );
    }
    return _present(doc);
  }

  /// Edits a template. The previous text is kept as a version so queued
  /// notifications that used it stay reproducible.
  Future<Map<String, Object?>> updateTemplate(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'name', 'subject', 'body', 'active'});
    final name = r.str('name', min: 2, max: 80, required: false);
    final subject = r.str('subject', max: 150, required: false);
    final text = r.str('body', min: 3, max: 1000, required: false);
    final active = r.boolean('active');
    r.throwIfInvalid();
    return _d.store.transaction((tx) async {
      final path = _p(t, 'notification_templates', id);
      final cur = await tx.get(path);
      if (cur == null) throw const ApiException.notFound('Template not found.');
      final issues = _checkText('${cur['eventType']}', subject, text);
      if (issues.isNotEmpty) throw ApiException.validation(issues);
      final v = (cur['version'] as int?) ?? 1;
      final patch = <String, Object?>{
        'name': ?name,
        'subject': ?subject,
        'body': ?text,
        'active': ?active,
        'version': v + 1,
        'updatedAt': _d.now,
        'updatedBy': t.uid,
      };
      tx.write([
        CreateOp(_p(t, 'notification_template_versions', '${id}_v$v'), {
          ...cur,
          'archivedAt': _d.now,
        }),
        UpdateOp(path, patch),
        _audit(
          t,
          'notification_template.updated',
          'template',
          id,
          requestId: requestId,
          after: {'version': v + 1},
        ),
      ]);
      return _present({...cur, ...patch});
    });
  }

  /// Renders a template with sample or given values. Nothing is sent.
  Future<Map<String, Object?>> preview(
    TenantContext t,
    String id,
    Map<String, Object?> body,
  ) async {
    t.require(ClinicPermission.notificationsManage);
    final r = BodyReader(body)..rejectUnknown({'variables'});
    Map<String, String> given = {};
    if (r.has('variables')) {
      final v = r.body['variables'];
      if (v is! Map || v.values.any((e) => e is! String || e.length > 100)) {
        r.addIssue('variables', 'invalid_value', 'Give short text values.');
      } else {
        given = v.map((k, e) => MapEntry('$k', e as String));
      }
    }
    r.throwIfInvalid();
    String type, subject, text, channel;
    if (id.startsWith('builtin:')) {
      final parts = id.split(':');
      final b = builtinTemplates
          .where(
            (x) =>
                parts.length == 3 &&
                x.eventType == parts[1] &&
                x.channel == parts[2],
          )
          .firstOrNull;
      if (b == null) throw const ApiException.notFound('Template not found.');
      type = b.eventType;
      channel = b.channel;
      subject = b.subject;
      text = b.body;
    } else {
      final cur = await _d.store.get(_p(t, 'notification_templates', id));
      if (cur == null) throw const ApiException.notFound('Template not found.');
      type = '${cur['eventType']}';
      channel = '${cur['channel']}';
      subject = '${cur['subject'] ?? ''}';
      text = '${cur['body']}';
    }
    const sample = {
      'clinicName': 'Sample Clinic',
      'doctorName': 'Dr Sample',
      'date': '2026-01-15',
      'time': '10:30',
    };
    final values = {...sample, ...given};
    try {
      final html = channel == 'email';
      return {
        'subject': renderTemplate(
          subject,
          values,
          allowed: variablesFor(type),
          html: html,
        ),
        'body': renderTemplate(
          text,
          values,
          allowed: variablesFor(type),
          html: html,
        ),
        'html': html,
        'note': 'Preview only. Nothing was sent.',
      };
    } on TemplateException catch (e) {
      throw ApiException.validation([
        _issue('variables', 'template_error', e.message),
      ]);
    }
  }

  // ----------------------------------------------------------- deliveries

  Future<Paged> deliveries(
    TenantContext t,
    Request req, {
    String? status,
    String? channel,
    String? type,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    if (status != null && !deliveryStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (channel != null && !notificationChannels.contains(channel)) {
      throw const ApiException.badRequest('channel has an unsupported value.');
    }
    return runPaged(
      _d.store,
      DocQuery(
        _p(t, 'notification_deliveries'),
        filters: [
          if (!t.scope.allBranches && t.scope.branchIds.length <= 30)
            QueryFilter(
              'branchId',
              FilterOp.inList,
              t.scope.branchIds.toList(),
            ),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (channel != null) QueryFilter('channel', FilterOp.eq, channel),
          if (type != null) QueryFilter('type', FilterOp.eq, type),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  /// Monitoring view: no title, body or recipient reference.
  Map<String, Object?> presentDelivery(DocData d) => {
    for (final k in const [
      'deliveryId',
      'eventId',
      'type',
      'channel',
      'recipientType',
      'status',
      'attempts',
      'error',
      'providerMessageId',
      'templateRef',
      'templateVersion',
      'manualRetries',
      'createdAt',
      'lastAttemptAt',
      'nextAttemptAt',
      'sentAt',
      'deliveredAt',
    ])
      if (d[k] != null) k: _safe(d[k]),
  };

  Future<Map<String, Object?>> retry(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    final result = await _d.store.transaction((tx) async {
      final path = _p(t, 'notification_deliveries', id);
      final d = await tx.get(path);
      if (d == null) throw const ApiException.notFound('Delivery not found.');
      if (!t.scope.allBranches &&
          d['branchId'] != null &&
          !t.scope.allows('${d['branchId']}')) {
        throw const ApiException.notFound('Delivery not found.');
      }
      final st = '${d['status']}';
      if (st == 'queued' || st == 'retry_scheduled' || st == 'processing') {
        return {...presentDelivery(d), 'idempotentReplay': true};
      }
      if (st != 'permanently_failed' && st != 'configuration_required') {
        throw ApiException.conflict('A $st delivery cannot be retried.');
      }
      final patch = {
        'status': 'queued',
        'nextAttemptAt': _d.now,
        'attempts': 0,
        'error': null,
        'manualRetries': ((d['manualRetries'] as int?) ?? 0) + 1,
      };
      tx.write([
        UpdateOp(path, patch),
        _audit(
          t,
          'notification_delivery.retried',
          'delivery',
          id,
          requestId: requestId,
          after: {'from': st},
        ),
      ]);
      return presentDelivery({...d, ...patch});
    });
    if (result['idempotentReplay'] != true) {
      await hub.dispatch(t.tenantId, id);
      final d = await _d.store.get(_p(t, 'notification_deliveries', id));
      if (d != null) return presentDelivery(d);
    }
    return result;
  }

  // ------------------------------------------------------------- channels

  Map<String, Object?> _channelConfigured(String ch) => {
    'configured': switch (ch) {
      'in_app' => true,
      'push' => _fcm.configured,
      _ => _providers[ch]?.configured ?? false,
    },
  };

  Future<List<Map<String, Object?>>> channels(TenantContext t) async {
    t.require(ClinicPermission.notificationsManage);
    final st = await hub.settings(t.tenantId);
    final on = st['channels']! as Set<String>;
    return [
      for (final ch in notificationChannels)
        {
          'channel': ch,
          ..._channelConfigured(ch),
          'enabledForClinic': on.contains(ch),
          'paused': await hub.channelPaused(t.tenantId, ch),
          if (!(_channelConfigured(ch)['configured']! as bool))
            'status': 'configuration_required',
        },
    ];
  }

  Future<Map<String, Object?>> setPaused(
    TenantContext t,
    String channel,
    bool paused, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    if (!notificationChannels.contains(channel)) {
      throw const ApiException.notFound('Channel not found.');
    }
    final path = _p(t, 'notification_channel_configs', channel);
    final cur = await _d.store.get(path);
    final doc = {
      'channel': channel,
      'tenantId': t.tenantId,
      'paused': paused,
      'updatedBy': t.uid,
      'updatedAt': _d.now,
    };
    await _d.store.commit([
      cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
      _audit(
        t,
        paused ? 'notification_channel.paused' : 'notification_channel.resumed',
        'channel',
        channel,
        requestId: requestId,
      ),
    ]);
    return {'channel': channel, 'paused': paused};
  }

  Future<Map<String, Object?>> settings(TenantContext t) async {
    t.require(ClinicPermission.notificationsManage);
    final s = await hub.settings(t.tenantId);
    return {
      'channels': (s['channels']! as Set<String>).toList()..sort(),
      'reminderLeadMinutes': s['reminderLeadMinutes'],
      'followupLeadDays': s['followupLeadDays'],
      'locale': s['locale'],
    };
  }

  Future<Map<String, Object?>> updateSettings(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.notificationsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({
        'channels',
        'reminderLeadMinutes',
        'followupLeadDays',
        'locale',
      });
    List<String>? channels;
    if (r.has('channels')) {
      final v = r.body['channels'];
      if (v is! List || v.any((e) => !notificationChannels.contains(e))) {
        r.addIssue('channels', 'invalid_value', 'Give known channels.');
      } else {
        channels = {...v.cast<String>(), 'in_app'}.toList();
      }
    }
    List<int>? leads;
    if (r.has('reminderLeadMinutes')) {
      final v = r.body['reminderLeadMinutes'];
      if (v is! List ||
          v.length > 4 ||
          v.any((e) => e is! int || e < 15 || e > 10080)) {
        r.addIssue(
          'reminderLeadMinutes',
          'invalid_value',
          'Give up to 4 values between 15 minutes and 7 days.',
        );
      } else {
        leads = v.cast<int>().toSet().toList()..sort();
      }
    }
    final days = r.integer(
      'followupLeadDays',
      min: 0,
      max: 14,
      required: false,
    );
    final locale = r.str('locale', min: 2, max: 2, required: false);
    if (locale != null && !_locale.hasMatch(locale)) {
      r.addIssue('locale', 'invalid_value', 'Use a two-letter language code.');
    }
    r.throwIfInvalid();
    final path = _p(t, 'notification_settings', 'main');
    final cur = await _d.store.get(path);
    final doc = {
      'tenantId': t.tenantId,
      ...?cur,
      'channels': ?channels,
      'reminderLeadMinutes': ?leads,
      'followupLeadDays': ?days,
      'locale': ?locale,
      'updatedBy': t.uid,
      'updatedAt': _d.now,
    };
    await _d.store.commit([
      cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
      _audit(
        t,
        'notification_settings.updated',
        'settings',
        'main',
        requestId: requestId,
      ),
    ]);
    return settings(t);
  }

  /// Delivery health: counts only, never content.
  Future<Map<String, Object?>> health(TenantContext t) async {
    t.require(ClinicPermission.notificationsManage);
    final rows = await _d.store.query(
      DocQuery(_p(t, 'notification_deliveries'), limit: 2000),
    );
    final byStatus = <String, int>{};
    final byChannel = <String, Map<String, int>>{};
    for (final r in rows) {
      final s = '${r.data['status']}';
      byStatus[s] = (byStatus[s] ?? 0) + 1;
      final c = byChannel.putIfAbsent('${r.data['channel']}', () => {});
      c[s] = (c[s] ?? 0) + 1;
    }
    final pending = await _d.store.query(
      DocQuery(
        _p(t, 'notification_events'),
        filters: const [
          QueryFilter('status', FilterOp.inList, ['pending', 'processing']),
        ],
        limit: 500,
      ),
    );
    return {
      'deliveries': byStatus,
      'byChannel': byChannel,
      'retryBacklog':
          (byStatus['retry_scheduled'] ?? 0) + (byStatus['queued'] ?? 0),
      'failed': byStatus['permanently_failed'] ?? 0,
      'configurationRequired': byStatus['configuration_required'] ?? 0,
      'eventsWaiting': pending.length,
      'truncated': rows.length >= 2000,
      'generatedAt': _d.now.toUtc().toIso8601String(),
      'note':
          'Sent means a provider accepted the message; it is not confirmation that it was received.',
    };
  }

  /// Used by tests and tools that need an id.
  String newDeviceNonce() => newId();
}
