@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/firestore_document_store.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/document_store_contract.dart';

/// The emulator treats "Bearer owner" as an admin credential.
class _OwnerClient extends http.BaseClient {
  _OwnerClient(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// Runs the production REST store against the Firestore emulator. Skipped
/// unless `FIRESTORE_EMULATOR_HOST` is set (see scripts/test_emulator.sh).
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  group(
    'FirestoreDocumentStore contract (emulator)',
    () {
      documentStoreContract(
        () => FirestoreDocumentStore(
          projectId: 'demo-eazyclinic',
          host: 'http://$host',
          client: _OwnerClient(http.Client()),
        ),
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
