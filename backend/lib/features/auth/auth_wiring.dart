import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/data/firestore_document_store.dart';
import '../../core/logging/app_logger.dart';
import 'application/account_service.dart';
import 'application/security_event_recorder.dart';
import 'application/token_verifier.dart';
import 'data/document_platform_user_store.dart';
import 'data/firebase_auth_admin.dart';
import 'data/signing_key_provider.dart';
import 'domain/access_resolver.dart';
import 'presentation/auth_routes.dart';

/// Builds the production [AuthModule] from configuration.
///
/// Returns `null` when no Firebase project is configured (dev only; config
/// validation requires it elsewhere). Credentials come from Application
/// Default Credentials — never from the repository.
Future<AuthModule?> buildProductionAuthModule(
  AppConfig config,
  AppLogger logger,
) async {
  final projectId = config.firebaseProjectId;
  if (projectId == null) {
    logger.warning('auth_not_configured', {
      'reason': 'FIREBASE_PROJECT_ID is not set',
    });
    return null;
  }
  final authed = await clientViaApplicationDefaultCredentials(
    scopes: const [
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/datastore',
    ],
  );
  final store = DocumentPlatformUserStore(
    FirestoreDocumentStore(projectId: projectId, client: authed),
  );
  final admin = IdentityToolkitAuthAdmin(projectId: projectId, client: authed);
  final events = SecurityEventRecorder(logger, store);
  return AuthModule(
    verifier: FirebaseTokenVerifier(
      projectId: projectId,
      keys: GoogleSigningKeyProvider(client: http.Client()),
    ),
    authAdmin: admin,
    accounts: AccountService(store: store, authAdmin: admin, events: events),
    access: const NoMembershipsAccessResolver(),
    events: events,
    checkRevoked: config.authCheckRevoked,
    trustForwardedFor: config.trustForwardedFor,
  );
}
