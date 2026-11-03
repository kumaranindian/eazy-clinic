import 'package:firebase_core/firebase_core.dart';
import 'package:utilities/utilities.dart';

/// Initializes Firebase for this environment from validated build-time
/// configuration. Firebase client identifiers are not secrets; service-account
/// keys never belong in an app.
Future<void> initializeFirebase(FirebaseClientConfig config) async {
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: config.apiKey,
      appId: config.appId,
      messagingSenderId: config.messagingSenderId,
      projectId: config.projectId,
      authDomain: config.authDomain,
    ),
  );
}
