// Backup/restore drill helper for the Firestore EMULATOR (never production).
//
//   dart run tool/restore_drill.dart seed   <checksum-file>
//   dart run tool/restore_drill.dart verify <checksum-file>
//
// `seed` writes a deterministic data set (clinic, patients, appointments,
// invoices, a nested sub-collection, timestamps, nested maps/lists) and writes
// a SHA-256 over every document it wrote. `verify` reads everything back and
// compares. Run `seed`, export the emulator, start a fresh emulator importing
// that export, then run `verify`.
import 'dart:convert';
import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class _Client extends http.BaseClient {
  _Client(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

const _collections = {
  'patients': 800,
  'appointments': 1500,
  'invoices': 600,
  'lab_orders': 300,
  'notification_events': 400,
};

Map<String, Object?> _doc(String c, int i) => {
  'id': '$c-$i',
  'n': i,
  'text': 'record $i of $c',
  'amount': i * 137 % 100000,
  'at': DateTime.utc(2026, 6, 1).add(Duration(minutes: i)),
  'nested': {
    'list': [i, i + 1, i + 2],
    'flag': i.isEven,
    'child': {'k': 'v$i'},
  },
};

String _digest(Map<String, Map<String, Object?>> docs) {
  final keys = docs.keys.toList()..sort();
  final h = sha256.convert(
    utf8.encode(keys.map((k) => '$k=${jsonEncode(_norm(docs[k]))}').join('\n')),
  );
  return h.toString();
}

Object? _norm(Object? v) {
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is Map) {
    final keys = v.keys.map((e) => '$e').toList()..sort();
    return {for (final k in keys) k: _norm(v[k])};
  }
  if (v is List) return v.map(_norm).toList();
  return v;
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || !const {'seed', 'verify'}.contains(args[0])) {
    stderr.writeln('usage: restore_drill.dart seed|verify <checksum-file>');
    exit(64);
  }
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  if (host == null) {
    stderr.writeln(
      'Refusing to run: FIRESTORE_EMULATOR_HOST is not set (emulator only).',
    );
    exit(64);
  }
  final store = FirestoreDocumentStore(
    projectId: 'demo-eazyclinic',
    host: 'http://$host',
    client: _Client(http.Client()),
  );
  const root = 'tenants/drill_tenant';
  final sw = Stopwatch()..start();
  if (args[0] == 'seed') {
    final all = <String, Map<String, Object?>>{};
    final ops = <WriteOp>[];
    Future<void> flush() async {
      if (ops.isEmpty) return;
      await store.commit(List.of(ops));
      ops.clear();
    }

    for (final e in _collections.entries) {
      for (var i = 0; i < e.value; i++) {
        final path = '$root/${e.key}/${e.key}_$i';
        final d = _doc(e.key, i);
        all[path] = d;
        ops.add(CreateOp(path, d));
        if (ops.length >= 400) await flush();
      }
    }
    // a document with a nested sub-collection
    for (var i = 0; i < 20; i++) {
      final path = '$root/patients/patients_$i/history/entry_$i';
      final d = _doc('history', i);
      all[path] = d;
      ops.add(CreateOp(path, d));
    }
    await flush();
    File(args[1]).writeAsStringSync(
      jsonEncode({'documents': all.length, 'sha256': _digest(all)}),
    );
    stdout.writeln(
      'seeded ${all.length} documents in ${sw.elapsedMilliseconds} ms',
    );
    return;
  }

  final expected = jsonDecode(File(args[1]).readAsStringSync()) as Map;
  final all = <String, Map<String, Object?>>{};
  for (final e in _collections.entries) {
    final rows = await store.query(DocQuery('$root/${e.key}', limit: 5000));
    for (final r in rows) {
      all[r.path] = r.data;
    }
  }
  for (var i = 0; i < 20; i++) {
    final path = '$root/patients/patients_$i/history/entry_$i';
    final d = await store.get(path);
    if (d != null) all[path] = d;
  }
  final ok =
      all.length == expected['documents'] && _digest(all) == expected['sha256'];
  stdout.writeln(
    'verified ${all.length}/${expected['documents']} documents in ${sw.elapsedMilliseconds} ms: ${ok ? 'MATCH' : 'MISMATCH'}',
  );
  exit(ok ? 0 : 1);
}
