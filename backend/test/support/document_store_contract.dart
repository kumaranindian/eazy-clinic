import 'package:backend/core/data/document_store.dart';
import 'package:test/test.dart';

/// Behaviour every [DocumentStore] must have. Run against the in-memory
/// double (always) and the real Firestore REST store (on the emulator).
void documentStoreContract(
  DocumentStore Function() create, {
  String Function() prefix = _defaultPrefix,
}) {
  late DocumentStore store;
  late String p; // unique collection prefix per test (emulator is shared)

  setUp(() {
    store = create();
    p = prefix();
  });

  test('get → null for a missing document', () async {
    expect(await store.get('$p/missing'), isNull);
  });

  test('create/get round-trips every supported type', () async {
    final data = <String, Object?>{
      's': 'text',
      'b': true,
      'i': 42,
      'd': 1.5,
      'n': null,
      't': DateTime.utc(2026, 1, 2, 3, 4, 5),
      'l': ['a', 1, true],
      'm': {
        'x': 1,
        'nested': {'y': 'z'},
      },
    };
    await store.commit([CreateOp('$p/a', data)]);
    expect(await store.get('$p/a'), data);
  });

  test('duplicate create → AlreadyExistsException', () async {
    await store.commit([
      CreateOp('$p/a', {'v': 1}),
    ]);
    expect(
      store.commit([
        CreateOp('$p/a', {'v': 2}),
      ]),
      throwsA(isA<AlreadyExistsException>()),
    );
    expect((await store.get('$p/a'))!['v'], 1);
  });

  test('update merges only given fields; null clears', () async {
    await store.commit([
      CreateOp('$p/a', {'x': 1, 'y': 2}),
    ]);
    await store.commit([
      UpdateOp('$p/a', {'x': 9, 'z': null}),
    ]);
    expect(await store.get('$p/a'), {'x': 9, 'y': 2, 'z': null});
  });

  test('update of a missing document → NotFoundException', () async {
    expect(
      store.commit([
        UpdateOp('$p/ghost', {'x': 1}),
      ]),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('commit is atomic: a failing op rolls back the others', () async {
    await store.commit([
      CreateOp('$p/exists', {'v': 1}),
    ]);
    await expectLater(
      store.commit([
        CreateOp('$p/new', {'v': 1}),
        CreateOp('$p/exists', {'v': 2}),
      ]),
      throwsA(isA<AlreadyExistsException>()),
    );
    expect(await store.get('$p/new'), isNull);
  });

  test(
    'delete removes a document, is idempotent, and is atomic with other ops',
    () async {
      await store.commit([
        CreateOp('$p/gone', {'v': 1}),
      ]);
      await store.commit([
        DeleteOp('$p/gone'),
        CreateOp('$p/kept', {'v': 2}),
      ]);
      expect(await store.get('$p/gone'), isNull);
      expect((await store.get('$p/kept'))!['v'], 2);
      await store.commit([DeleteOp('$p/gone')]); // already gone: no error
      await expectLater(
        store.commit([
          DeleteOp('$p/kept'),
          CreateOp('$p/kept2', {}),
          CreateOp('$p/kept2', {}),
        ]),
        throwsA(isA<Object>()),
      );
      expect(
        await store.get('$p/kept'),
        isNotNull,
        reason: 'rolled back with the failed commit',
      );
    },
  );

  group('queries', () {
    setUp(() async {
      await store.commit([
        for (var i = 1; i <= 7; i++)
          CreateOp('$p/d$i', {
            'n': i,
            'grp': i.isEven ? 'even' : 'odd',
            'tags': i == 3 ? ['x', 'y'] : ['y'],
            'at': DateTime.utc(2026, 1, i),
          }),
      ]);
    });

    List<String> ids(List<StoredDoc> d) => d.map((e) => e.id).toList();

    test('equality + ordering + limit', () async {
      final r = await store.query(
        DocQuery(
          p,
          filters: const [QueryFilter('grp', FilterOp.eq, 'odd')],
          orderBy: const OrderBy('n', descending: true),
          limit: 2,
        ),
      );
      expect(ids(r), ['d7', 'd5']);
    });

    test('range, in and array-contains filters', () async {
      expect(
        ids(
          await store.query(
            DocQuery(
              p,
              filters: [
                const QueryFilter('n', FilterOp.gte, 3),
                const QueryFilter('n', FilterOp.lt, 6),
              ],
              orderBy: const OrderBy('n'),
            ),
          ),
        ),
        ['d3', 'd4', 'd5'],
      );
      expect(
        ids(
          await store.query(
            DocQuery(
              p,
              filters: [
                const QueryFilter('n', FilterOp.inList, [1, 2]),
              ],
              orderBy: const OrderBy('n'),
            ),
          ),
        ),
        ['d1', 'd2'],
      );
      expect(
        ids(
          await store.query(
            DocQuery(
              p,
              filters: [const QueryFilter('tags', FilterOp.arrayContains, 'x')],
            ),
          ),
        ),
        ['d3'],
      );
    });

    test('cursor pagination walks every document exactly once', () async {
      for (final desc in [false, true]) {
        final seen = <String>[];
        PageCursor? cursor;
        for (var guard = 0; guard < 10; guard++) {
          final page = await store.query(
            DocQuery(
              p,
              orderBy: OrderBy('at', descending: desc),
              limit: 3,
              after: cursor,
            ),
          );
          if (page.isEmpty) break;
          seen.addAll(ids(page));
          cursor = PageCursor(page.last.data['at'], page.last.id);
        }
        expect(
          seen.toSet(),
          hasLength(7),
          reason: 'no duplicates (desc=$desc)',
        );
        expect(seen.first, desc ? 'd7' : 'd1');
        expect(seen.last, desc ? 'd1' : 'd7');
      }
    });

    test('count honours filters', () async {
      expect(await store.count(DocQuery(p)), 7);
      expect(
        await store.count(
          DocQuery(p, filters: const [QueryFilter('grp', FilterOp.eq, 'even')]),
        ),
        3,
      );
    });
  });

  test(
    'subcollections are scoped to their parent; collection groups span them',
    () async {
      await store.commit([
        CreateOp('$p/t1/members/u1', {'uid': 'u1', 'status': 'active'}),
        CreateOp('$p/t2/members/u1', {'uid': 'u1', 'status': 'active'}),
        CreateOp('$p/t2/members/u2', {'uid': 'u2', 'status': 'active'}),
      ]);
      expect(await store.count(DocQuery('$p/t1/members')), 1);
      expect(await store.count(DocQuery('$p/t2/members')), 2);
      final group = await store.query(
        DocQuery(
          'members',
          collectionGroup: true,
          filters: [const QueryFilter('uid', FilterOp.eq, 'u1')],
        ),
      );
      final mine = group
          .where((d) => d.path.startsWith('$p/'))
          .map((d) => d.path);
      expect(mine.toSet(), {'$p/t1/members/u1', '$p/t2/members/u1'});
    },
  );

  group('transactions', () {
    test('read-modify-write commits atomically', () async {
      await store.commit([
        CreateOp('$p/counter', {'n': 1}),
      ]);
      await store.transaction((tx) async {
        final n = (await tx.get('$p/counter'))!['n']! as int;
        tx.write([
          UpdateOp('$p/counter', {'n': n + 1}),
          CreateOp('$p/log', {'v': n}),
        ]);
      });
      expect((await store.get('$p/counter'))!['n'], 2);
      expect((await store.get('$p/log'))!['v'], 1);
    });

    test('writes are discarded when the body throws', () async {
      await expectLater(
        store.transaction((tx) async {
          tx.write([
            CreateOp('$p/ghost', {'v': 1}),
          ]);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await store.get('$p/ghost'), isNull);
    });

    test('queries inside a transaction see committed data', () async {
      await store.commit([
        CreateOp('$p/q1', {'k': 'a'}),
      ]);
      final found = await store.transaction(
        (tx) => tx.query(
          DocQuery(p, filters: const [QueryFilter('k', FilterOp.eq, 'a')]),
        ),
      );
      expect(found.map((d) => d.id), ['q1']);
    });
  });

  test('concurrent creates of the same id: exactly one wins', () async {
    // The idempotency primitive used by tenant provisioning.
    final results = await Future.wait([
      for (var i = 0; i < 6; i++)
        store
            .commit([
              CreateOp('$p/once', {'by': i}),
            ])
            .then((_) => 'created')
            .catchError((Object _) => 'exists'),
    ]);
    expect(results.where((r) => r == 'created'), hasLength(1));
  });
}

int _n = 0;
String _defaultPrefix() => 'ct${DateTime.now().microsecondsSinceEpoch}_${_n++}';
