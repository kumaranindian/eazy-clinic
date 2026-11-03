import 'dart:math';

import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';

import '../responses/responses.dart';

final Random _random = Random.secure();

String _newRequestId() {
  final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Assigns every request a correlation id (always server-generated: a client
/// supplied id is never trusted or echoed) and returns it as `x-request-id`.
Middleware requestIdMiddleware() {
  return (inner) => (request) async {
    final id = _newRequestId();
    final response = await inner(
      request.change(context: {requestIdContextKey: id}),
    );
    return response.change(headers: {requestIdHeader: id});
  };
}
