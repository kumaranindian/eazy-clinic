import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/portal_repository.dart';

/// Where the device's push token comes from.
///
/// Firebase Cloud Messaging is not wired into this build: that needs the
/// `firebase_messaging` plugin and an environment's `google-services.json`,
/// which are release configuration (see PATIENT_ANDROID_RELEASE_CHECKLIST.md).
/// Until then the default source reports no token, the app registers nothing
/// and the in-app notification list still works. Replacing this class is the
/// only change needed to turn on push delivery.
abstract interface class PushTokenSource {
  /// A stable id for this install and the current FCM token, or null.
  Future<({String deviceId, String token})?> current();
}

class NoPushTokenSource implements PushTokenSource {
  const NoPushTokenSource();

  @override
  Future<({String deviceId, String token})?> current() async => null;
}

final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => const NoPushTokenSource(),
);

/// Registers this device with the backend after sign-in, refreshes it when the
/// token changes, and deactivates it on sign-out.
class PushRegistrar {
  PushRegistrar(this._repo, this._source);

  final PortalRepository _repo;
  final PushTokenSource _source;
  String? _deviceId;

  Future<bool> register() async {
    final t = await _source.current();
    if (t == null) return false;
    try {
      await _repo.send('POST', '/patient/devices', {
        'deviceId': t.deviceId,
        'token': t.token,
        'platform': 'android',
      });
      _deviceId = t.deviceId;
      return true;
    } on ApiFailure {
      return false;
    }
  }

  Future<void> unregister() async {
    final id = _deviceId ?? (await _source.current())?.deviceId;
    if (id == null) return;
    try {
      await _repo.send('DELETE', '/patient/devices/$id');
    } on ApiFailure {
      // the session is ending anyway; the backend also drops tokens it cannot reach
    }
    _deviceId = null;
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>(
  (ref) => PushRegistrar(
    ref.watch(portalRepositoryProvider),
    ref.watch(pushTokenSourceProvider),
  ),
);
