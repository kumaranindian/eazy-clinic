import 'package:googleapis_auth/auth_io.dart';

import 'config/app_config.dart';
import 'core/data/firestore_document_store.dart';
import 'core/logging/app_logger.dart';
import 'features/auth/auth_wiring.dart';
import 'features/auth/presentation/auth_routes.dart';
import 'features/clinic/clinic_module.dart';
import 'features/clinic/common/object_storage.dart';
import 'features/platform/platform_module.dart';

/// Production dependency graph. Credentials come from Application Default
/// Credentials only. Returns nulls when no Firebase project is configured
/// (dev only); protected routes then answer 503.
Future<({AuthModule? auth, PlatformModule? platform, ClinicModule? clinic})>
buildProductionModules(AppConfig config, AppLogger logger) async {
  final projectId = config.firebaseProjectId;
  if (projectId == null) {
    logger.warning('auth_not_configured', {
      'reason': 'FIREBASE_PROJECT_ID is not set',
    });
    return (auth: null, platform: null, clinic: null);
  }
  final authed = await clientViaApplicationDefaultCredentials(
    scopes: const [
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/datastore',
    ],
  );
  final store = FirestoreDocumentStore(projectId: projectId, client: authed);
  final auth = buildAuthModule(
    config: config,
    logger: logger,
    projectId: projectId,
    store: store,
    authedClient: authed,
  );
  final bucket = config.storageBucket;
  return (
    auth: auth,
    platform: PlatformModule(auth: auth, store: store),
    clinic: ClinicModule(
      auth: auth,
      store: store,
      storage: bucket == null
          ? const UnconfiguredObjectStorage()
          : GcsObjectStorage(bucket: bucket, client: authed),
    ),
  );
}
