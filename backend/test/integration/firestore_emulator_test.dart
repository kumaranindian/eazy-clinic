@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/features/auth/data/firestore_platform_user_store.dart';
import 'package:backend/features/auth/data/platform_user_store.dart';
import 'package:backend/features/auth/domain/platform_user.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Runs the production [FirestorePlatformUserStore] against the Firestore
/// emulator (never a real project). Skipped unless `FIRESTORE_EMULATOR_HOST`
/// is set, e.g. via `scripts/test_emulator.sh`.
class _OwnerClient extends http.BaseClient {
  _OwnerClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // The emulator treats "Bearer owner" as an admin credential.
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  late FirestorePlatformUserStore store;

  setUp(() {
    store = FirestorePlatformUserStore(
      projectId: 'demo-eazyclinic',
      host: 'http://$host',
      client: _OwnerClient(http.Client()),
    );
  });

  PlatformUser user(String uid) => PlatformUser(
    uid: uid,
    displayName: 'Emulator User',
    email: '$uid@example.test',
    emailVerified: false,
    accountStatus: AccountStatus.pending,
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  );

  group(
    'FirestorePlatformUserStore on the emulator',
    () {
      test('get → null for a missing document', () async {
        expect(
          await store.get('missing-${DateTime.now().microsecondsSinceEpoch}'),
          isNull,
        );
      });

      test(
        'create then get round-trips every field incl. timestamps',
        () async {
          final uid = 'u-${DateTime.now().microsecondsSinceEpoch}';
          await store.create(user(uid));
          final loaded = (await store.get(uid))!;
          expect(loaded.uid, uid);
          expect(loaded.accountStatus, AccountStatus.pending);
          expect(loaded.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
          expect(loaded.lastLoginAt, isNull);
          expect(loaded.platformRole, isNull);
        },
      );

      test(
        'duplicate create → AlreadyExistsException (no duplicate profile)',
        () async {
          final uid = 'dup-${DateTime.now().microsecondsSinceEpoch}';
          await store.create(user(uid));
          expect(
            store.create(user(uid)),
            throwsA(isA<AlreadyExistsException>()),
          );
        },
      );

      test('update changes only the masked fields', () async {
        final uid = 'upd-${DateTime.now().microsecondsSinceEpoch}';
        await store.create(user(uid));
        await store.update(uid, {
          'accountStatus': 'active',
          'lastLoginAt': DateTime.utc(2026, 2, 1),
        });
        final loaded = (await store.get(uid))!;
        expect(loaded.accountStatus, AccountStatus.active);
        expect(loaded.lastLoginAt, DateTime.utc(2026, 2, 1));
        expect(loaded.email, '$uid@example.test', reason: 'untouched field');
      });

      test('update clears a field with null', () async {
        final uid = 'null-${DateTime.now().microsecondsSinceEpoch}';
        await store.create(user(uid));
        await store.update(uid, {'phoneNumber': '9876543210'});
        await store.update(uid, {'phoneNumber': null});
        expect((await store.get(uid))!.phoneNumber, isNull);
      });

      test(
        'update of a missing document fails instead of creating it',
        () async {
          expect(
            store.update('ghost-${DateTime.now().microsecondsSinceEpoch}', {
              'accountStatus': 'active',
            }),
            throwsA(isA<StoreException>()),
          );
        },
      );

      test('appendAuditLog writes a document', () async {
        await store.appendAuditLog({
          'event': 'logout',
          'uid': 'u1',
          'outcome': 'success',
          'timestamp': DateTime.now().toUtc(),
        });
      });
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
