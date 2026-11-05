import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';

const List<String> providerStatuses = ['candidate', 'approved', 'disabled'];
const List<String> gatewayModes = ['test', 'live'];

final RegExp _providerKey = RegExp(r'^[a-z][a-z0-9_]{1,29}$');

bool isProviderKey(String? k) => k != null && _providerKey.hasMatch(k);

/// Country / currency / provider eligibility (`payment_eligibility/{country}`),
/// managed by platform administrators.
///
/// Candidate providers are **only candidates** (`status: candidate`, no
/// modes). A provider can be `approved` only when an adapter for it exists in
/// this deployment, and `live` mode only when the deployment explicitly
/// enables live payments *and* the entry is marked `liveApproved`. In this
/// phase live payments are hard-disabled.
class PaymentEligibilityService {
  PaymentEligibilityService(
    this._store,
    this._audit, {
    required this.adapterModes,
    this.livePaymentsEnabled = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  /// Adapter id -> modes it supports in this deployment.
  final Map<String, Set<String>> adapterModes;

  /// Deployment-level switch; off unless explicitly approved.
  final bool livePaymentsEnabled;

  static const String collection = 'payment_eligibility';

  DateTime get _now => _clock().toUtc();

  Map<String, Object?> present(Map<String, Object?> d) =>
      jsonSafe(d)! as Map<String, Object?>;

  Map<String, Object?> _candidate(String id, String currency, String name) => {
    'provider': id,
    'name': name,
    'currencies': [currency],
    'modes': <String>[],
    'status': 'candidate',
    'liveApproved': false,
    'note':
        'Candidate subject to commercial and technical validation. No adapter '
        'exists; it cannot be enabled.',
  };

  Map<String, Object?> _sandbox(String currency) => {
    'provider': 'sandbox',
    'name': 'Sandbox (test only, moves no money)',
    'currencies': [currency],
    'modes': ['test'],
    'status': 'approved',
    'liveApproved': false,
    'note': 'Deterministic stand-in for contract tests and rehearsals.',
  };

  List<Map<String, Object?>> baseline() => [
    {
      'countryCode': 'IN',
      'providers': [
        _sandbox('INR'),
        _candidate('razorpay', 'INR', 'Razorpay'),
        _candidate('cashfree', 'INR', 'Cashfree'),
        _candidate('payu', 'INR', 'PayU'),
      ],
    },
    {
      'countryCode': 'AE',
      'providers': [
        _sandbox('AED'),
        _candidate('telr', 'AED', 'Telr'),
        _candidate('network_international', 'AED', 'Network International'),
        _candidate('checkout_com', 'AED', 'Checkout.com'),
      ],
    },
  ];

  Future<List<Map<String, Object?>>> list() async {
    final rows = await _store.query(DocQuery(collection, limit: 100));
    return [for (final r in rows) present(r.data)]
      ..sort((a, b) => '${a['countryCode']}'.compareTo('${b['countryCode']}'));
  }

  Future<DocData?> raw(String country) =>
      RegExp(r'^[A-Z]{2}$').hasMatch(country)
      ? _store.get('$collection/$country')
      : Future.value(null);

  Future<List<Map<String, Object?>>> seedBaseline(
    Actor actor, {
    String? requestId,
  }) async {
    final out = <Map<String, Object?>>[];
    for (final b in baseline()) {
      final cc = b['countryCode']! as String;
      try {
        await _store.commit([
          CreateOp('$collection/$cc', {
            ...b,
            'version': 1,
            'createdAt': _now,
            'updatedAt': _now,
            'updatedBy': actor.uid,
          }),
          _audit.op(
            AuditEntry(
              actor: actor,
              action: 'payment_eligibility.seeded',
              targetType: 'payment_eligibility',
              targetId: cc,
              requestId: requestId,
            ),
          ),
        ]);
        out.add({'countryCode': cc, 'created': true});
      } on AlreadyExistsException {
        out.add({'countryCode': cc, 'created': false});
      }
    }
    return out;
  }

  static const Set<String> _fields = {
    'expectedVersion',
    'reason',
    'status',
    'currencies',
    'modes',
    'liveApproved',
    'note',
  };

  /// Changes one provider's eligibility in one country.
  Future<Map<String, Object?>> updateProvider(
    String country,
    String provider,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body, partial: true)..rejectUnknown(_fields);
    final expected = r.integer('expectedVersion', min: 1, max: 100000);
    final reason = r.str('reason', min: 3, max: 300);
    final status = r.enumOf<String>(
      'status',
      providerStatuses,
      (v) => v,
      required: false,
    );
    final note = r.str('note', max: 300, required: false);
    final live = r.boolean('liveApproved');
    List<String>? currencies;
    if (r.has('currencies')) {
      final c = r.body['currencies'];
      if (c is! List ||
          c.isEmpty ||
          c.length > 5 ||
          c.any((e) => e is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(e))) {
        r.addIssue('currencies', 'invalid_value', 'Give 1-5 ISO 4217 codes.');
      } else {
        currencies = c.cast<String>();
      }
    }
    List<String>? modes;
    if (r.has('modes')) {
      final m = r.body['modes'];
      if (m is! List || m.any((e) => !gatewayModes.contains(e))) {
        r.addIssue('modes', 'invalid_value', 'Use test and/or live.');
      } else {
        modes = m.cast<String>();
      }
    }
    r.throwIfInvalid();
    if (!isProviderKey(provider) || !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      throw const ApiException.notFound('Provider not found.');
    }
    late Map<String, Object?> saved;
    await _store.transaction((tx) async {
      final cur = await tx.get('$collection/$country');
      if (cur == null) {
        throw const ApiException.notFound('Provider not found.');
      }
      if (cur['version'] != expected) {
        throw const ApiException.conflict(
          'Changed by someone else. Reload and try again.',
        );
      }
      final list = [
        for (final p in (cur['providers']! as List))
          (p! as Map).cast<String, Object?>(),
      ];
      final i = list.indexWhere((p) => p['provider'] == provider);
      if (i < 0) throw const ApiException.notFound('Provider not found.');
      final next = {
        ...list[i],
        'status': ?status,
        'currencies': ?currencies,
        'modes': ?modes,
        'liveApproved': ?live,
        'note': ?note,
      };
      final nextStatus = next['status'];
      final nextModes = (next['modes']! as List).cast<String>();
      if (nextStatus == 'approved') {
        final supported = adapterModes[provider];
        if (supported == null) {
          throw ApiException.conflict(
            'No adapter exists for "$provider" in this deployment, so it cannot be approved.',
          );
        }
        if (nextModes.isEmpty || !nextModes.every(supported.contains)) {
          throw ApiException.conflict(
            'The adapter for "$provider" supports: ${supported.join(', ')}.',
          );
        }
      }
      if (nextModes.contains('live') || next['liveApproved'] == true) {
        if (!livePaymentsEnabled) {
          throw const ApiException.conflict(
            'Live payments are disabled in this deployment.',
          );
        }
        if (nextStatus != 'approved') {
          throw const ApiException.conflict(
            'Only an approved provider can be live.',
          );
        }
      }
      if (nextStatus != 'approved' && nextModes.isNotEmpty) {
        throw const ApiException.conflict(
          'A provider that is not approved cannot have modes.',
        );
      }
      list[i] = next;
      final version = (cur['version']! as int) + 1;
      saved = {
        ...cur,
        'providers': list,
        'version': version,
        'updatedAt': _now,
        'updatedBy': actor.uid,
      };
      tx.write([
        UpdateOp('$collection/$country', saved),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'payment_eligibility.updated',
            targetType: 'payment_eligibility',
            targetId: '$country/$provider',
            requestId: requestId,
            reason: reason,
            before: {'version': cur['version'], 'status': list[i]['status']},
            after: {'version': version, 'status': nextStatus},
          ),
        ),
      ]);
    });
    return present(saved);
  }

  /// Provider health across all clinics (counts only, no payer data).
  Future<Map<String, Object?>> health() async {
    final configs = await _store.query(
      DocQuery('gateway_config', collectionGroup: true, limit: 2000),
    );
    final byProvider = <String, Map<String, Object?>>{};
    Map<String, Object?> row(String p) => byProvider.putIfAbsent(
      p,
      () => {
        'provider': p,
        'clinicsConfigured': 0,
        'clinicsEnabled': 0,
        'liveClinics': 0,
        'openExceptions': 0,
        'transactions': <String, int>{},
      },
    );
    for (final c in configs) {
      final x = row('${c.data['provider']}');
      x['clinicsConfigured'] = (x['clinicsConfigured']! as int) + 1;
      if (c.data['enabled'] == true) {
        x['clinicsEnabled'] = (x['clinicsEnabled']! as int) + 1;
      }
      if (c.data['mode'] == 'live') {
        x['liveClinics'] = (x['liveClinics']! as int) + 1;
      }
    }
    final txs = await _store.query(
      DocQuery('gateway_transactions', collectionGroup: true, limit: 5000),
    );
    for (final t in txs) {
      final m =
          row('${t.data['provider']}')['transactions']! as Map<String, int>;
      m['${t.data['status']}'] = (m['${t.data['status']}'] ?? 0) + 1;
    }
    final ex = await _store.query(
      DocQuery(
        'gateway_exceptions',
        collectionGroup: true,
        filters: [const QueryFilter('status', FilterOp.eq, 'open')],
        limit: 5000,
      ),
    );
    final unattributed = <String, Object?>{};
    for (final e in ex) {
      final tx = e.data['transactionId'];
      final prov = tx == null
          ? null
          : txs
                .where((t) => t.data['transactionId'] == tx)
                .map((t) => '${t.data['provider']}')
                .firstOrNull;
      if (prov == null) {
        unattributed['count'] = ((unattributed['count'] as int?) ?? 0) + 1;
      } else {
        final x = row(prov);
        x['openExceptions'] = (x['openExceptions']! as int) + 1;
      }
    }
    return {
      'livePaymentsEnabled': livePaymentsEnabled,
      'providers': byProvider.values.toList(),
      'unattributedOpenExceptions': unattributed['count'] ?? 0,
      'truncated': txs.length >= 5000 || configs.length >= 2000,
    };
  }
}
