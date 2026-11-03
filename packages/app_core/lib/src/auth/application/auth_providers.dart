import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_audience.dart';
import '../domain/auth_api.dart';
import '../domain/auth_repository.dart';

/// Overridden in each app's `main()` with the Firebase-backed implementation
/// (and with test doubles in tests).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw StateError('authRepositoryProvider must be overridden.'),
);

/// Overridden in each app's `main()`.
final authApiProvider = Provider<AuthApi>(
  (ref) => throw StateError('authApiProvider must be overridden.'),
);

/// Which app is running; decides which resolved access opens it.
final appAudienceProvider = Provider<AppAudience>(
  (ref) => throw StateError('appAudienceProvider must be overridden.'),
);
