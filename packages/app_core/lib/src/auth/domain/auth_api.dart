import 'package:api_contracts/api_contracts.dart';

/// Backend authentication API (`/api/v1/auth`).
abstract interface class AuthApi {
  /// `GET /auth/session`.
  Future<AuthSessionDto> getSession();

  /// `POST /auth/provision`: first-time profile creation and login record.
  Future<AuthSessionDto> provision();

  /// `POST /auth/logout`.
  Future<void> logout({bool allDevices = false});
}

/// An error envelope returned by the backend (or a transport failure).
class AuthApiException implements Exception {
  const AuthApiException({this.code, this.isNetwork = false});

  final ApiErrorCode? code;
  final bool isNetwork;

  @override
  String toString() => 'AuthApiException(${code?.wireName ?? 'network'})';
}
