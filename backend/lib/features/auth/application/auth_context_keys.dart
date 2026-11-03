import 'package:shelf/shelf.dart';

import '../domain/auth_context.dart';
import '../domain/verified_identity.dart';

const String _identityKey = 'eazyclinic.auth.identity';
const String _contextKey = 'eazyclinic.auth.context';

Request withIdentity(Request request, VerifiedIdentity identity) =>
    request.change(context: {_identityKey: identity});

Request withAuthContext(Request request, AuthContext context) =>
    request.change(context: {_contextKey: context});

/// The verified token identity. Throws if the token middleware did not run
/// (a wiring bug, not a client error).
VerifiedIdentity identityOf(Request request) {
  final v = request.context[_identityKey];
  if (v is! VerifiedIdentity) {
    throw StateError('tokenAuthMiddleware must run before this handler.');
  }
  return v;
}

/// The full server-derived authorization context. Throws if the account
/// middleware did not run.
AuthContext authContextOf(Request request) {
  final v = request.context[_contextKey];
  if (v is! AuthContext) {
    throw StateError('accountMiddleware must run before this handler.');
  }
  return v;
}
