import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/data/document_store.dart';
import '../../core/logging/app_logger.dart';
import 'application/account_service.dart';
import 'application/security_event_recorder.dart';
import 'application/token_verifier.dart';
import 'data/document_platform_user_store.dart';
import 'data/firebase_auth_admin.dart';
import 'data/membership_access_resolver.dart';
import 'data/signing_key_provider.dart';
import 'presentation/auth_routes.dart';

/// Builds the production [AuthModule]. Clinic memberships are resolved from
/// trusted `tenants/{id}/members` documents.
AuthModule buildAuthModule({
  required AppConfig config,
  required AppLogger logger,
  required String projectId,
  required DocumentStore store,
  required http.Client authedClient,
}) {
  final users = DocumentPlatformUserStore(store);
  final admin = IdentityToolkitAuthAdmin(
    projectId: projectId,
    client: authedClient,
  );
  final events = SecurityEventRecorder(logger, users);
  return AuthModule(
    verifier: FirebaseTokenVerifier(
      projectId: projectId,
      keys: GoogleSigningKeyProvider(client: http.Client()),
    ),
    authAdmin: admin,
    accounts: AccountService(store: users, authAdmin: admin, events: events),
    access: MembershipAccessResolver(store),
    events: events,
    checkRevoked: config.authCheckRevoked,
    trustForwardedFor: config.trustForwardedFor,
  );
}
