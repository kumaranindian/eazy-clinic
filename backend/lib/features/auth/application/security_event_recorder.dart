import '../../../core/logging/app_logger.dart';
import '../data/platform_user_store.dart';

/// Security-relevant authentication events.
enum SecurityEvent {
  userProvisioned('user_provisioned'),
  loginRecorded('login_recorded'),
  loginDenied('login_denied'),
  accountActivated('account_activated'),
  logout('logout'),
  sessionsRevoked('sessions_revoked'),
  accessDenied('access_denied'),
  tokenRejected('token_rejected'),
  rateLimited('rate_limited');

  const SecurityEvent(this.wireName);
  final String wireName;
}

/// Writes security events to the structured log and, best effort, to
/// `platform_audit_logs`. Events never contain tokens, e-mail addresses or
/// names — only ids, event type, outcome and a short reason code.
class SecurityEventRecorder {
  SecurityEventRecorder(this._logger, this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppLogger _logger;
  final PlatformUserStore? _store;
  final DateTime Function() _clock;

  Future<void> record(
    SecurityEvent event, {
    String? uid,
    String? actorUid,
    String? requestId,
    String outcome = 'success',
    String? reason,
    bool persist = true,
  }) async {
    final fields = <String, Object?>{
      'event': event.wireName,
      'uid': uid,
      'actorUid': actorUid,
      'requestId': requestId,
      'outcome': outcome,
      'reason': reason,
    };
    if (outcome == 'success') {
      _logger.info('security_event', fields);
    } else {
      _logger.warning('security_event', fields);
    }
    final store = _store;
    if (!persist || store == null) return;
    try {
      await store.appendAuditLog({...fields, 'timestamp': _clock().toUtc()});
    } on Object {
      // Audit persistence must not break the request; the log line above is
      // the fallback record.
      _logger.error('audit_persist_failed', {'event': event.wireName});
    }
  }
}
