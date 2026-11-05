import 'dart:convert';
import 'dart:math';

import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../scheduling/time_support.dart';
import 'notification_core.dart';

String _h(String s) => sha256.convert(utf8.encode(s)).toString();

class _Recipient {
  const _Recipient(this.type, this.ref);

  /// `patient_account` (ref = account id) or `staff` (ref = uid).
  final String type;
  final String ref;
  String get key => '$type:$ref';
}

/// The one notification pipeline: event (outbox) -> recipients -> templates ->
/// deliveries -> provider adapters -> tracked outcomes.
///
/// * Events are durable documents; a worker (or the caller, inline) processes
///   them, and a crashed worker's events are picked up again after the lease.
/// * Everything is idempotent: event ids come from the dedupe key, delivery and
///   inbox ids are deterministic, so a replay creates nothing twice.
/// * Recipients are resolved from trusted records only, preferences and the
///   channel switch are re-checked at dispatch time, and stale reminders are
///   suppressed.
/// * A provider "accepted" is recorded as `sent`, never as `delivered`.
class NotificationHub {
  NotificationHub(
    this._d, {
    FcmSender fcm = const UnconfiguredFcmSender(),
    Map<String, MessageProvider> providers = const {},
    Random? random,
    this.lease = const Duration(minutes: 5),
  }) : _fcm = fcm,
       _providers = providers,
       _rng = random ?? Random();

  final ClinicDeps _d;
  final FcmSender _fcm;
  final Map<String, MessageProvider> _providers;
  final Random _rng;
  final Duration lease;

  String _p(String tenantId, String c, [String? id]) =>
      'tenants/$tenantId/$c${id == null ? '' : '/$id'}';

  // -------------------------------------------------------------- settings

  Future<Map<String, Object?>> settings(String tenantId) async {
    final s = await _d.store.get(_p(tenantId, 'notification_settings', 'main'));
    final channels = <String>{
      ...((s?['channels'] as List?)?.cast<String>() ?? defaultChannels),
      'in_app',
    };
    return {
      'channels': channels,
      'reminderLeadMinutes':
          (s?['reminderLeadMinutes'] as List?)?.cast<int>() ??
          const [1440, 120],
      'followupLeadDays': (s?['followupLeadDays'] as int?) ?? 1,
      'locale': (s?['locale'] as String?) ?? 'en',
    };
  }

  Future<bool> channelPaused(String tenantId, String channel) async {
    final c = await _d.store.get(
      _p(tenantId, 'notification_channel_configs', channel),
    );
    return c?['paused'] == true;
  }

  // ----------------------------------------------------------------- emit

  /// Records a domain event. Replays of the same [dedupeKey] return the same
  /// id and change nothing. [variables] hold only the non-clinical values the
  /// event's templates may use; [fallbackTitle]/[fallbackBody] are used when
  /// no template exists for the event type.
  Future<String> emit({
    required String tenantId,
    required String type,
    required String dedupeKey,
    String? branchId,
    String? patientId,
    String? accountId,
    String? staffDoctorId,
    String? staffUid,
    String? resourceType,
    String? resourceId,
    Map<String, String> variables = const {},
    Map<String, String> data = const {},
    String? fallbackTitle,
    String? fallbackBody,
  }) async {
    final id = 'ev_${_h('$tenantId:$dedupeKey').substring(0, 24)}';
    try {
      await _d.store.commit([
        CreateOp(
          _p(tenantId, 'notification_events', id),
          {
            'eventId': id,
            'tenantId': tenantId,
            'type': type,
            'dedupeKey': dedupeKey,
            'branchId': branchId,
            'patientId': patientId,
            'accountId': accountId,
            'staffDoctorId': staffDoctorId,
            'staffUid': staffUid,
            'resourceType': resourceType,
            'resourceId': resourceId,
            'variables': variables,
            'data': data,
            'fallbackTitle': fallbackTitle,
            'fallbackBody': fallbackBody,
            'status': 'pending',
            'attempts': 0,
            'createdAt': _d.now,
          }..removeWhere((k, v) => v == null),
        ),
      ]);
    } on AlreadyExistsException {
      // already recorded
    }
    return id;
  }

  // ------------------------------------------------------------ recipients

  Future<List<_Recipient>> _recipients(String tenantId, DocData e) async {
    final out = <_Recipient>[];
    var account = e['accountId'] as String?;
    if (account == null && e['patientId'] != null) {
      final p = await _d.store.get(
        _p(tenantId, 'patients', '${e['patientId']}'),
      );
      if (p != null && p['status'] == 'active') {
        account = p['patientAccountId'] as String?;
      }
    }
    if (account != null) out.add(_Recipient('patient_account', account));
    if (e['staffUid'] != null) out.add(_Recipient('staff', '${e['staffUid']}'));
    if (e['staffDoctorId'] != null) {
      final rows = await _d.store.query(
        DocQuery(
          _p(tenantId, 'members'),
          filters: [QueryFilter('doctorId', FilterOp.eq, e['staffDoctorId'])],
          limit: 5,
        ),
      );
      for (final m in rows) {
        if (m.data['status'] == 'active') {
          out.add(_Recipient('staff', '${m.data['uid'] ?? m.id}'));
        }
      }
    }
    return out;
  }

  Future<Map<String, Object?>> _prefs(String tenantId, _Recipient r) async {
    final doc = await _d.store.get(
      r.type == 'patient_account'
          ? 'patient_notification_preferences/${r.ref}'
          : _p(tenantId, 'notification_preferences', r.ref),
    );
    return doc ?? const {};
  }

  /// Whether [channel] may carry [category] for someone with [prefs].
  static bool allowed(Map<String, Object?> prefs, String channel, String cat) {
    final cats = (prefs['categories'] as Map?)?.cast<String, Object?>() ?? {};
    if (promotionalCategories.contains(cat)) {
      if (cats[cat] != true) return false; // explicit opt-in only
    } else if (!essentialCategories.contains(cat) && cats[cat] == false) {
      return false;
    }
    switch (channel) {
      case 'in_app':
        // essential entries stay; optional categories honour the opt-out
        return essentialCategories.contains(cat) || cats[cat] != false;
      case 'push':
        return prefs['pushEnabled'] != false && cats[cat] != false;
      default:
        final ch = (prefs['channels'] as Map?)?.cast<String, Object?>() ?? {};
        return ch[channel] != false && cats[cat] != false;
    }
  }

  // --------------------------------------------------------------- render

  Future<({String title, String body, String ref, int version})?> _render(
    String tenantId,
    DocData e,
    String channel,
    String locale,
  ) async {
    final type = '${e['type']}';
    final vars = ((e['variables'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', '$v'),
    );
    final allowedVars = variablesFor(type);
    // an event with no variables carries its own ready-made text (one-off
    // service messages); templates are for events that bring variables
    final ft = e['fallbackTitle'] as String?;
    final fb = e['fallbackBody'] as String?;
    if (vars.isEmpty && (ft != null || fb != null)) {
      return (
        title: ft ?? 'Notification',
        body: fb ?? '',
        ref: 'fallback',
        version: 0,
      );
    }
    // an active tenant template wins over the built-in one
    final rows = await _d.store.query(
      DocQuery(
        _p(tenantId, 'notification_templates'),
        filters: [
          QueryFilter('eventType', FilterOp.eq, type),
          QueryFilter('channel', FilterOp.eq, channel),
          const QueryFilter('active', FilterOp.eq, true),
        ],
        limit: 10,
      ),
    );
    final mine =
        rows.where((r) => r.data['locale'] == locale).firstOrNull ??
        rows.where((r) => r.data['locale'] == 'en').firstOrNull;
    String? subject;
    String? body;
    var ref = 'fallback';
    var version = 0;
    if (mine != null) {
      subject = '${mine.data['subject'] ?? ''}';
      body = '${mine.data['body']}';
      ref = mine.id;
      version = (mine.data['version'] as int?) ?? 1;
    } else {
      final forEvent = builtinTemplates.where(
        (t) => t.eventType == type && t.channel == channel,
      );
      // the recipient's language when a template exists, else English
      final b =
          forEvent.where((t) => t.locale == locale).firstOrNull ??
          forEvent.where((t) => t.locale == 'en').firstOrNull;
      if (b != null) {
        subject = b.subject;
        body = b.body;
        ref = 'builtin:$type:$channel';
        version = b.version;
      }
    }
    final html = channel == 'email';
    if (subject == null && body == null) {
      final t = e['fallbackTitle'] as String?;
      final b = e['fallbackBody'] as String?;
      if (t == null && b == null) return null;
      return (title: t ?? 'Notification', body: b ?? '', ref: ref, version: 0);
    }
    // right-to-left text: keep names, numbers and identifiers in their own
    // direction (only when the chosen template really is in that language)
    final usedLocale = mine != null ? '${mine.data['locale']}' : locale;
    final rtl = rtlUiLanguages.contains(usedLocale);
    return (
      title: renderTemplate(
        subject ?? '',
        vars,
        allowed: allowedVars,
        html: html,
        rtl: rtl,
      ),
      body: renderTemplate(
        body ?? '',
        vars,
        allowed: allowedVars,
        html: html,
        rtl: rtl,
      ),
      ref: ref,
      version: version,
    );
  }

  // --------------------------------------------------------- stale checks

  /// Why [e] should no longer be sent, or null.
  Future<String?> staleReason(String tenantId, DocData e) async {
    final type = '${e['type']}';
    final data = (e['data'] as Map?) ?? const {};
    // only scheduled reminders carry the details they must still match; the
    // same category also serves one-off messages that are never stale
    if (type == 'appointment_reminder' && data['startUtc'] != null) {
      final a = await _d.store.get(
        _p(tenantId, 'appointments', '${e['resourceId']}'),
      );
      if (a == null || a['status'] != 'confirmed') {
        return 'appointment_no_longer_confirmed';
      }
      final was = (e['data'] as Map?)?['startUtc'];
      final now = (a['startUtc'] as DateTime?)?.toUtc().toIso8601String();
      if (was != now) return 'appointment_rescheduled';
      if (!(a['startUtc'] as DateTime).isAfter(_d.now)) {
        return 'appointment_passed';
      }
    }
    if (type == 'followup_reminder' && data['date'] != null) {
      final f = await _d.store.get(
        _p(tenantId, 'followups', '${e['resourceId']}'),
      );
      if (f == null || f['status'] != 'scheduled') {
        return 'followup_no_longer_active';
      }
      if ((e['data'] as Map?)?['date'] != f['recommendedDate']) {
        return 'followup_date_changed';
      }
    }
    return null;
  }

  // --------------------------------------------------------- processing

  /// Processes pending (and lease-expired) events of one clinic.
  Future<int> processPending(String tenantId, {int limit = 25}) async {
    final rows = await _d.store.query(
      DocQuery(
        _p(tenantId, 'notification_events'),
        filters: [
          const QueryFilter('status', FilterOp.inList, [
            'pending',
            'processing',
          ]),
        ],
        limit: limit,
      ),
    );
    var n = 0;
    for (final r in rows) {
      if (await processEvent(tenantId, r.id)) n++;
    }
    return n;
  }

  /// Processes one event. Returns false when it was not this caller's to do.
  Future<bool> processEvent(String tenantId, String eventId) async {
    final path = _p(tenantId, 'notification_events', eventId);
    final now = _d.now;
    final claimed = await _d.store.transaction((tx) async {
      final e = await tx.get(path);
      if (e == null) return null;
      final st = e['status'];
      final until = e['leaseUntil'] as DateTime?;
      if (st == 'processed' || st == 'suppressed') return null;
      if (st == 'processing' && until != null && until.isAfter(now)) {
        return null;
      }
      tx.write([
        UpdateOp(path, {
          'status': 'processing',
          'leaseUntil': now.add(lease),
          'attempts': ((e['attempts'] as int?) ?? 0) + 1,
        }),
      ]);
      return e;
    });
    if (claimed == null) return false;
    final e = claimed;

    final stale = await staleReason(tenantId, e);
    if (stale != null) {
      await _d.store.commit([
        UpdateOp(path, {
          'status': 'suppressed',
          'suppressedReason': stale,
          'processedAt': _d.now,
        }),
      ]);
      return true;
    }

    final st = await settings(tenantId);
    final channels = st['channels']! as Set<String>;
    final locale = '${st['locale']}';
    final category = '${e['type']}';
    final ops = <WriteOp>[];
    final now2 = _d.now;
    for (final r in await _recipients(tenantId, e)) {
      final prefs = await _prefs(tenantId, r);
      for (final ch in notificationChannels) {
        if (!channels.contains(ch) || !allowed(prefs, ch, category)) continue;
        final did = 'dl_${_h('${e['eventId']}:${r.key}:$ch').substring(0, 24)}';
        final base = <String, Object?>{
          'deliveryId': did,
          'eventId': e['eventId'],
          'tenantId': tenantId,
          'branchId': e['branchId'],
          'type': category,
          'channel': ch,
          'recipientType': r.type,
          'recipientRef': r.ref,
          'patientId': e['patientId'],
          'attempts': 0,
          'createdAt': now2,
        };
        ({String title, String body, String ref, int version})? msg;
        try {
          msg = await _render(tenantId, e, ch, locale);
        } on TemplateException catch (x) {
          ops.add(
            CreateOp(
              _p(tenantId, 'notification_deliveries', did),
              {
                ...base,
                'status': 'permanently_failed',
                'error': 'template_error: ${x.message}',
              }..removeWhere((k, v) => v == null),
            ),
          );
          continue;
        }
        if (msg == null) continue;
        final doc = <String, Object?>{
          ...base,
          'title': msg.title,
          'body': msg.body,
          'templateRef': msg.ref,
          'templateVersion': msg.version,
        };
        if (ch == 'in_app') {
          final nid =
              'n_${_h('${r.type == 'patient_account' ? r.ref : '$tenantId:${r.ref}'}:${e['dedupeKey']}').substring(0, 24)}';
          final inbox = <String, Object?>{
            'notificationId': nid,
            'category': category,
            'title': msg.title,
            'body': msg.body,
            'clinicId': tenantId,
            'resourceType': e['resourceType'],
            'resourceId': e['resourceId'],
            'read': false,
            'archived': false,
            'createdAt': now2,
          }..removeWhere((k, v) => v == null);
          if (r.type == 'patient_account') {
            inbox['accountId'] = r.ref;
            ops.add(CreateOp('patient_notifications/$nid', inbox));
          } else {
            inbox
              ..['tenantId'] = tenantId
              ..['recipientUid'] = r.ref;
            ops.add(CreateOp(_p(tenantId, 'notifications', nid), inbox));
          }
          ops.add(
            CreateOp(
              _p(tenantId, 'notification_deliveries', did),
              {
                ...doc,
                'status': 'delivered',
                'attempts': 1,
                'deliveredAt': now2,
              }..removeWhere((k, v) => v == null),
            ),
          );
        } else {
          ops.add(
            CreateOp(
              _p(tenantId, 'notification_deliveries', did),
              {...doc, 'status': 'queued', 'nextAttemptAt': now2}
                ..removeWhere((k, v) => v == null),
            ),
          );
        }
      }
    }
    // the event completes in the same write as its deliveries: a crash before
    // this point leaves it processing and it is picked up again after the lease
    ops.add(UpdateOp(path, {'status': 'processed', 'processedAt': now2}));
    try {
      await _d.store.commit(ops);
    } on AlreadyExistsException {
      // a previous, interrupted run already created some of them: write the
      // missing ones one by one
      for (final op in ops) {
        try {
          await _d.store.commit([op]);
        } on AlreadyExistsException {
          continue;
        }
      }
    }
    return true;
  }

  // ------------------------------------------------------------- dispatch

  /// Sends queued and due retry deliveries of one clinic.
  Future<int> dispatchDue(String tenantId, {int limit = 50}) async {
    final rows = await _d.store.query(
      DocQuery(
        _p(tenantId, 'notification_deliveries'),
        filters: [
          const QueryFilter('status', FilterOp.inList, [
            'queued',
            'retry_scheduled',
          ]),
          QueryFilter('nextAttemptAt', FilterOp.lte, _d.now),
        ],
        limit: limit,
      ),
    );
    var n = 0;
    for (final r in rows) {
      if (await dispatch(tenantId, r.id)) n++;
    }
    return n;
  }

  Future<bool> dispatch(String tenantId, String deliveryId) async {
    final path = _p(tenantId, 'notification_deliveries', deliveryId);
    final claimed = await _d.store.transaction((tx) async {
      final d = await tx.get(path);
      if (d == null) return null;
      if (d['status'] != 'queued' && d['status'] != 'retry_scheduled') {
        return null;
      }
      tx.write([
        UpdateOp(path, {
          'status': 'processing',
          'attempts': ((d['attempts'] as int?) ?? 0) + 1,
          'lastAttemptAt': _d.now,
        }),
      ]);
      return d;
    });
    if (claimed == null) return false;
    final d = claimed;
    final attempts = ((d['attempts'] as int?) ?? 0) + 1;
    final ch = '${d['channel']}';

    Future<bool> finish(
      String status, {
      String? error,
      String? messageId,
      DateTime? next,
    }) async {
      await _d.store.commit([
        UpdateOp(path, {
          'status': status,
          'error': error,
          'providerMessageId': messageId,
          'nextAttemptAt': next,
          if (status == 'sent') 'sentAt': _d.now,
        }),
      ]);
      return true;
    }

    // paused channel: keep the record queued, try again later
    if (await channelPaused(tenantId, ch)) {
      await _d.store.commit([
        UpdateOp(path, {
          'status': 'queued',
          'attempts': attempts - 1,
          'nextAttemptAt': _d.now.add(const Duration(minutes: 5)),
        }),
      ]);
      return false;
    }
    // revalidate right before sending
    final ev = await _d.store.get(
      _p(tenantId, 'notification_events', '${d['eventId']}'),
    );
    if (ev != null) {
      final stale = await staleReason(tenantId, ev);
      if (stale != null) return finish('cancelled', error: stale);
    }
    final r = _Recipient('${d['recipientType']}', '${d['recipientRef']}');
    final prefs = await _prefs(tenantId, r);
    if (!allowed(prefs, ch, '${d['type']}')) {
      return finish('cancelled', error: 'recipient_preference');
    }
    if (!((await settings(tenantId))['channels']! as Set<String>).contains(
      ch,
    )) {
      return finish('cancelled', error: 'channel_disabled');
    }

    ProviderResult res;
    if (ch == 'push') {
      res = await _sendPush(tenantId, d, r);
    } else {
      final p = _providers[ch];
      if (p == null || !p.configured) {
        res = const ProviderResult('not_configured');
      } else {
        final addr = await _address(tenantId, d, ch);
        res = addr == null
            ? const ProviderResult('permanent', error: 'no_address')
            : await p.send(
                address: addr,
                subject: '${d['title']}',
                body: '${d['body']}',
              );
      }
    }
    switch (res.outcome) {
      case 'accepted':
        return finish('sent', messageId: res.messageId);
      case 'not_configured':
        return finish(
          'configuration_required',
          error: 'provider_not_configured',
        );
      case 'no_device':
        return finish('cancelled', error: 'no_active_device');
      case 'transient':
        if (attempts >= maxDeliveryAttempts) {
          return finish(
            'permanently_failed',
            error: res.error ?? 'retries_exhausted',
          );
        }
        return finish(
          'retry_scheduled',
          error: res.error,
          next: _d.now.add(backoff(attempts, _rng)),
        );
      default:
        return finish('permanently_failed', error: res.error ?? res.outcome);
    }
  }

  Future<String?> _address(String tenantId, DocData d, String ch) async {
    if (d['recipientType'] != 'patient_account' || d['patientId'] == null) {
      return null;
    }
    final p = await _d.store.get(_p(tenantId, 'patients', '${d['patientId']}'));
    final v = p?[ch == 'email' ? 'email' : 'phone'];
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<ProviderResult> _sendPush(
    String tenantId,
    DocData d,
    _Recipient r,
  ) async {
    if (!_fcm.configured) return const ProviderResult('not_configured');
    final rows = await _d.store.query(
      r.type == 'patient_account'
          ? DocQuery(
              'patient_devices',
              filters: [
                QueryFilter('accountId', FilterOp.eq, r.ref),
                const QueryFilter('active', FilterOp.eq, true),
              ],
              limit: 10,
            )
          : DocQuery(
              'notification_devices',
              filters: [
                QueryFilter('uid', FilterOp.eq, r.ref),
                const QueryFilter('active', FilterOp.eq, true),
              ],
              limit: 10,
            ),
    );
    if (rows.isEmpty) return const ProviderResult('no_device');
    String? messageId;
    var transient = false;
    var accepted = false;
    String? lastError;
    for (final dev in rows) {
      final token = dev.data['token'] as String?;
      if (token == null) continue;
      final res = await _fcm.send(
        token: token,
        title: '${d['title']}',
        body: '${d['body']}',
        data: {
          'type': '${d['type']}',
          'deliveryId': '${d['deliveryId']}',
          'clinicId': tenantId,
        },
      );
      switch (res.outcome) {
        case 'accepted':
          accepted = true;
          messageId ??= res.messageId;
        case 'invalid_token':
          await _d.store.commit([
            UpdateOp(dev.path, {
              'active': false,
              'invalidatedAt': _d.now,
              'invalidReason': res.error,
            }),
          ]);
          lastError = res.error;
        case 'transient':
          transient = true;
          lastError = res.error;
        default:
          lastError = res.error ?? res.outcome;
      }
    }
    if (accepted) return ProviderResult('accepted', messageId: messageId);
    if (transient) return ProviderResult('transient', error: lastError);
    return ProviderResult('permanent', error: lastError ?? 'no_valid_token');
  }

  // -------------------------------------------------------------- reminders

  /// Creates reminder events for confirmed appointments and active follow-ups
  /// of one clinic. Re-running creates nothing new (dedupe keys).
  Future<int> scanReminders(String tenantId) async {
    final st = await settings(tenantId);
    final leads = [...(st['reminderLeadMinutes']! as List<int>)]..sort();
    final zoneDoc = await _d.store.get(
      _p(tenantId, 'clinic_settings', 'operations'),
    );
    final zone = ClinicZone.resolve(zoneDoc?['timezone'] as String?);
    final now = _d.now;
    final today = zone.localDate(now);
    final clinic = await _d.store.get('tenants/$tenantId');
    final clinicName = '${clinic?['clinicName'] ?? 'your clinic'}';
    var n = 0;
    final maxLead = leads.isEmpty ? 0 : leads.last;
    final lastDate = zone.localDate(now.add(Duration(minutes: maxLead + 60)));
    final appts = await _d.store.query(
      DocQuery(
        _p(tenantId, 'appointments'),
        filters: [
          const QueryFilter('status', FilterOp.eq, 'confirmed'),
          QueryFilter('localDate', FilterOp.gte, today),
          QueryFilter('localDate', FilterOp.lte, lastDate),
        ],
        limit: 2000,
      ),
    );
    for (final a in appts) {
      final start = (a.data['startUtc'] as DateTime?)?.toUtc();
      if (start == null || !start.isAfter(now)) continue;
      // the smallest lead that has already begun: one reminder per window
      int? lead;
      for (final l in leads) {
        if (!now.isBefore(start.subtract(Duration(minutes: l)))) {
          lead = l;
          break;
        }
      }
      if (lead == null) continue;
      await emit(
        tenantId: tenantId,
        type: 'appointment_reminder',
        dedupeKey: 'reminder:${a.id}:${start.toIso8601String()}:$lead',
        branchId: '${a.data['branchId']}',
        patientId: '${a.data['patientId']}',
        resourceType: 'appointment',
        resourceId: a.id,
        variables: {
          'clinicName': clinicName,
          'doctorName': '${a.data['doctorName'] ?? 'your doctor'}',
          'date': '${a.data['localDate']}',
          'time': '${a.data['startTime']}',
        },
        data: {'startUtc': start.toIso8601String()},
      );
      n++;
    }
    final days = st['followupLeadDays']! as int;
    final target = Dates.addDays(today, days);
    final fus = await _d.store.query(
      DocQuery(
        _p(tenantId, 'followups'),
        filters: [QueryFilter('recommendedDate', FilterOp.eq, target)],
        limit: 1000,
      ),
    );
    for (final f in fus) {
      if (f.data['status'] != 'scheduled') continue;
      await emit(
        tenantId: tenantId,
        type: 'followup_reminder',
        dedupeKey: 'followup:${f.id}:$target',
        branchId: '${f.data['branchId']}',
        patientId: '${f.data['patientId']}',
        resourceType: 'followup',
        resourceId: f.id,
        variables: {'clinicName': clinicName, 'date': target},
        data: {'date': target},
      );
      n++;
    }
    return n;
  }

  /// One worker pass over every active clinic. Safe to run concurrently with
  /// itself: claims are transactional.
  Future<void> tick({int maxTenants = 500}) async {
    final tenants = await _d.store.query(
      DocQuery(
        'tenants',
        filters: const [QueryFilter('status', FilterOp.eq, 'active')],
        limit: maxTenants,
      ),
    );
    for (final t in tenants) {
      try {
        await scanReminders(t.id);
        await processPending(t.id);
        await dispatchDue(t.id);
      } on Object {
        // one clinic's failure never stops the others; its records stay queued
        continue;
      }
    }
  }

  /// Convenience for the caller that just emitted [eventId].
  Future<void> processNow(String tenantId, String eventId) async {
    await processEvent(tenantId, eventId);
    await dispatchDue(tenantId, limit: 20);
  }

  /// Audit record (ids and reasons only, never message content).
  CreateOp audit(
    String tenantId, {
    required String actorUid,
    required String actorRole,
    required String action,
    required String resourceType,
    required String resourceId,
    String? reason,
    String? requestId,
    Map<String, Object?>? after,
  }) => CreateOp(
    _p(tenantId, 'notification_audit_logs', newId()),
    {
      'tenantId': tenantId,
      'action': action,
      'resourceType': resourceType,
      'resourceId': resourceId,
      'actorUid': actorUid,
      'actorRole': actorRole,
      'reason': reason,
      'requestId': requestId,
      'after': after,
      'timestamp': _d.now,
    }..removeWhere((k, v) => v == null),
  );
}
