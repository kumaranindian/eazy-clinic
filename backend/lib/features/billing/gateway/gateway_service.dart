import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../../clinic/common/tenant_context.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/entitlements/entitlement_service.dart';
import '../billing_support.dart';
import '../invoice_service.dart';
import '../payment_service.dart';
import '../refund_service.dart';
import 'payment_eligibility_service.dart';
import 'provider.dart';

/// How long a transaction may stay open before reconciliation lists it.
const Duration staleAfter = Duration(minutes: 30);

String _hash(String v) => sha256.convert(utf8.encode(v)).toString();

/// Online payments for one clinic: configuration, payment intents, verified
/// webhooks, refunds and reconciliation.
///
/// Rules this class enforces:
/// - the amount of an intent comes from the invoice, never from the client;
/// - a payment is recorded **only** from a verified provider event (or a
///   provider status inquiry), never from anything the client reports;
/// - every event is claimed once (replay-safe) and every state change follows
///   [gatewayTransitions];
/// - amount or currency that differ from the transaction are never recorded:
///   they open a reconciliation exception;
/// - settlement facts (currency, amount, fee, FX evidence) are stored apart
///   from the transaction amount and are never computed here;
/// - secrets are resolved from server configuration at call time and are
///   never stored or returned.
class GatewayService {
  GatewayService(
    this._s,
    this._payments,
    this._refunds,
    this._invoices,
    this._providers,
    this._creds, {
    this.livePaymentsEnabled = false,
  });

  final BillingSupport _s;
  final PaymentService _payments;
  final RefundService _refunds;
  final InvoiceService _invoices;
  final Map<String, PaymentProvider> _providers;
  final CredentialResolver _creds;
  final bool livePaymentsEnabled;

  static const String txCollection = 'gateway_transactions';

  Map<String, Object?> adapterModes() => {
    for (final p in _providers.values) p.id: p.modes,
  };

  // ------------------------------------------------------------ helpers

  DocumentStore get _store => _s.d.store;

  TenantContext _system(
    String tenantId,
    String providerId,
    Entitlements entitlements,
  ) => TenantContext(
    tenantId: tenantId,
    uid: 'gateway:$providerId',
    role: ClinicRole.clinicOwner,
    scope: const BranchScope(allBranches: true, branchIds: {}),
    entitlements: entitlements,
  );

  Map<String, Object?> presentTx(Map<String, Object?> d) {
    final out = BillingSupport.present(d);
    out.remove('idempotencyKey');
    return out;
  }

  Future<DocData?> _config(String tenantId) =>
      _store.get('tenants/$tenantId/gateway_config/main');

  Future<DocData?> _eligibility(String tenantId) async {
    final tenant = await _store.get('tenants/$tenantId');
    final cc = tenant?['countryCode'] as String?;
    if (cc == null) return null;
    return _store.get('${PaymentEligibilityService.collection}/$cc');
  }

  Map<String, Object?>? _entry(DocData? elig, String provider) {
    for (final p in (elig?['providers'] as List? ?? const [])) {
      final m = (p! as Map).cast<String, Object?>();
      if (m['provider'] == provider) return m;
    }
    return null;
  }

  // ------------------------------------------------------------- config

  Future<Map<String, Object?>> getConfig(TenantContext t) async {
    t.require(ClinicPermission.paymentView);
    final c = await _config(t.tenantId);
    final canManage = t.can(ClinicPermission.gatewayManage);
    final elig = await _eligibility(t.tenantId);
    final currency = await _s.currency(t);
    final eligible = [
      for (final p in (elig?['providers'] as List? ?? const []))
        if ((p! as Map)['status'] == 'approved' &&
            ((p['currencies'] as List?) ?? const []).contains(currency))
          {
            'provider': p['provider'],
            'name': p['name'],
            'modes': p['modes'],
            'capabilities': _providers['${p['provider']}']?.capabilities
                .toJson(),
          },
    ];
    final enabled = c?['enabled'] == true;
    return {
      'configured': c != null,
      'enabled': enabled,
      'provider': c?['provider'],
      'mode': c?['mode'],
      'credentialVersion': c?['credentialVersion'],
      if (canManage) 'credentialRef': c?['credentialRef'],
      'currency': currency,
      'livePaymentsEnabled': livePaymentsEnabled,
      'eligibleProviders': canManage ? eligible : const [],
    };
  }

  Future<Map<String, Object?>> putConfig(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.gatewayManage);
    final r = BodyReader(body)
      ..rejectUnknown({'provider', 'mode', 'credentialRef', 'enabled'});
    final provider = r.str('provider', max: 30);
    final mode = r.enumOf<String>('mode', gatewayModes, (v) => v);
    final ref = r.str('credentialRef', max: 40);
    final enabled = r.boolean('enabled') ?? true;
    r.throwIfInvalid();
    final adapter = _providers[provider];
    final elig = await _eligibility(t.tenantId);
    final entry = _entry(elig, '$provider');
    final currency = await _s.currency(t);
    if (adapter == null ||
        entry == null ||
        entry['status'] != 'approved' ||
        !((entry['currencies'] as List?) ?? const []).contains(currency) ||
        !((entry['modes'] as List?) ?? const []).contains(mode) ||
        !adapter.modes.contains(mode)) {
      throw const ApiException.conflict(
        'That provider is not approved for this clinic\'s country, currency and mode.',
      );
    }
    if (mode == 'live' &&
        (!livePaymentsEnabled || entry['liveApproved'] != true)) {
      throw const ApiException.conflict(
        'Live payments are not enabled. Use test mode.',
      );
    }
    if (_creds.resolve('$ref') == null) {
      throw ApiException.validation(const [
        FieldIssue(
          field: 'credentialRef',
          code: 'unknown',
          message: 'No such credential is configured on the server.',
        ),
      ]);
    }
    final p = _s.path(t, 'gateway_config', 'main');
    final cur = await _store.get(p);
    final now = _s.d.now;
    final doc = {
      'provider': provider,
      'mode': mode,
      'credentialRef': ref,
      'enabled': enabled,
      'credentialVersion': (cur?['credentialVersion'] as int?) ?? 1,
      'previousCredentialRef': cur?['previousCredentialRef'],
      'updatedAt': now,
      'updatedBy': t.uid,
    };
    await _store.commit([
      cur == null
          ? CreateOp(p, {...doc, 'createdAt': now, 'createdBy': t.uid})
          : UpdateOp(p, doc),
      _s.audit(
        t,
        action: 'gateway.configured',
        resourceType: 'gateway_config',
        resourceId: 'main',
        requestId: requestId,
        after: {'provider': provider, 'mode': mode, 'enabled': enabled},
      ),
    ]);
    return getConfig(t);
  }

  /// Switches to new credentials; the previous reference keeps verifying
  /// webhooks until [retirePrevious] is called, so in-flight events survive.
  Future<Map<String, Object?>> rotate(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.gatewayManage);
    final r = BodyReader(body)
      ..rejectUnknown({'credentialRef', 'retirePrevious'});
    final retire = r.boolean('retirePrevious') ?? false;
    final ref = r.str('credentialRef', max: 40, required: !retire);
    r.throwIfInvalid();
    final p = _s.path(t, 'gateway_config', 'main');
    final cur = await _store.get(p);
    if (cur == null) {
      throw const ApiException.conflict('No gateway is configured.');
    }
    final now = _s.d.now;
    Map<String, Object?> patch;
    if (retire) {
      patch = {'previousCredentialRef': null};
    } else {
      if (ref == cur['credentialRef']) {
        throw const ApiException.conflict('That is the current credential.');
      }
      if (_creds.resolve('$ref') == null) {
        throw ApiException.validation(const [
          FieldIssue(
            field: 'credentialRef',
            code: 'unknown',
            message: 'No such credential is configured on the server.',
          ),
        ]);
      }
      patch = {
        'credentialRef': ref,
        'previousCredentialRef': cur['credentialRef'],
        'credentialVersion': ((cur['credentialVersion'] as int?) ?? 1) + 1,
      };
    }
    await _store.commit([
      UpdateOp(p, {...patch, 'updatedAt': now, 'updatedBy': t.uid}),
      _s.audit(
        t,
        action: retire ? 'gateway.credential_retired' : 'gateway.rotated',
        resourceType: 'gateway_config',
        resourceId: 'main',
        requestId: requestId,
        after: {'credentialVersion': patch['credentialVersion']},
      ),
    ]);
    return getConfig(t);
  }

  // ------------------------------------------------------------- intents

  Future<Map<String, Object?>> createIntent(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.paymentCollect);
    final idem = _s.idem(t, 'gateway_intent', idempotencyKey, body);
    final r = BodyReader(body)..rejectUnknown({'invoiceId', 'amountMinor'});
    final invoiceId = r.str('invoiceId', max: 40);
    final wanted = r.integer(
      'amountMinor',
      min: 1,
      max: 100000000000,
      required: false,
    );
    r.throwIfInvalid();
    final c = await _config(t.tenantId);
    if (c == null || c['enabled'] != true) {
      throw const ApiException.conflict('Online payments are not enabled.');
    }
    final provider = _providers['${c['provider']}'];
    final creds = _creds.resolve('${c['credentialRef']}');
    if (provider == null || creds == null) {
      throw const ApiException.conflict(
        'Online payments are not available right now.',
      );
    }
    final inv = await _invoices.load(t, invoiceId!);
    if (!InvoiceService.acceptsPayment(inv)) {
      throw const ApiException.conflict(
        'This invoice has nothing outstanding or cannot take payments.',
      );
    }
    final due = inv['outstanding']! as int;
    final amount = wanted ?? due;
    if (amount > due) {
      throw ApiException.conflict('Only $due is outstanding on this invoice.');
    }
    final currency = '${inv['currency']}';
    final elig = await _eligibility(t.tenantId);
    final entry = _entry(elig, '${c['provider']}');
    if (entry == null ||
        !((entry['currencies'] as List?) ?? const []).contains(currency)) {
      throw const ApiException.conflict(
        'This provider does not accept the invoice currency.',
      );
    }
    final id = 'gtx_${newId(length: 14)}';
    final now = _s.d.now;
    final created = await _store.transaction((tx) async {
      final prior = await _s.priorIn(tx, idem);
      if (prior != null) return {'replay': prior['resourceId']};
      final open = await tx.query(
        DocQuery(
          _s.path(t, txCollection),
          filters: [QueryFilter('invoiceId', FilterOp.eq, invoiceId)],
          limit: 50,
        ),
      );
      if (open.any((d) => openGatewayStatuses.contains(d.data['status']))) {
        throw const ApiException.conflict(
          'An online payment for this invoice is already open.',
        );
      }
      final doc = <String, Object?>{
        'transactionId': id,
        'tenantId': t.tenantId,
        'branchId': inv['branchId'],
        'patientId': inv['patientId'],
        'invoiceId': invoiceId,
        'invoiceNumber': inv['invoiceNumber'],
        'provider': c['provider'],
        'mode': c['mode'],
        'amountMinor': amount,
        'currency': currency,
        'currencyExponent': currencyExponent[currency] ?? 2,
        'status': 'intent',
        'refundedTotal': 0,
        'paymentId': null,
        'providerRef': null,
        'settlement': null,
        'history': [
          {'at': now, 'to': 'intent'},
        ],
        'createdAt': now,
        'createdBy': t.uid,
        'updatedAt': now,
      };
      tx.write([
        CreateOp(_s.path(t, txCollection, id), doc),
        _s.record(idem, 'gateway_transaction', id),
        _s.audit(
          t,
          action: 'gateway.intent_created',
          resourceType: 'gateway_transaction',
          resourceId: id,
          branchId: '${inv['branchId']}',
          patientId: '${inv['patientId']}',
          invoiceId: invoiceId,
          requestId: requestId,
          amount: amount,
        ),
      ]);
      return {'doc': doc};
    });
    if (created['replay'] != null) {
      return {
        ...presentTx(
          (await _store.get(_s.path(t, txCollection, '${created['replay']}')))!,
        ),
        'idempotentReplay': true,
      };
    }
    final doc = created['doc']! as Map<String, Object?>;
    try {
      final intent = await provider.createIntent(
        IntentRequest(
          tenantId: t.tenantId,
          transactionId: id,
          amountMinor: amount,
          currency: currency,
          idempotencyKey: 'in_$id',
          reference: '${inv['invoiceNumber']}',
        ),
        creds,
      );
      final patch = {
        'status': 'pending',
        'providerRef': intent.providerRef,
        'history': [
          ...(doc['history']! as List),
          {'at': _s.d.now, 'to': 'pending'},
        ],
        'updatedAt': _s.d.now,
      };
      await _store.commit([UpdateOp(_s.path(t, txCollection, id), patch)]);
      return {
        ...presentTx({...doc, ...patch}),
        'checkoutToken': intent.checkoutToken,
      };
    } on Object {
      await _store.commit([
        UpdateOp(_s.path(t, txCollection, id), {
          'status': 'failed',
          'failureCode': 'provider_error',
          'history': [
            ...(doc['history']! as List),
            {'at': _s.d.now, 'to': 'failed'},
          ],
          'updatedAt': _s.d.now,
        }),
      ]);
      throw const ApiException(
        ApiErrorCode.unavailable,
        'The payment provider is not available. Try again later.',
      );
    }
  }

  // ---------------------------------------------------------------- reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.paymentView);
    final d = await _store.get(_s.path(t, txCollection, id));
    if (d == null || !t.scope.allows('${d['branchId']}')) {
      throw const ApiException.notFound('Transaction not found.');
    }
    return presentTx(d);
  }

  Future<List<Map<String, Object?>>> list(
    TenantContext t, {
    String? invoiceId,
    String? status,
  }) async {
    t.require(ClinicPermission.paymentView);
    final rows = await _store.query(
      DocQuery(
        _s.path(t, txCollection),
        filters: [
          ..._s.scopeFilters(t, null),
          if (invoiceId != null)
            QueryFilter('invoiceId', FilterOp.eq, invoiceId),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        limit: 200,
      ),
    );
    return [for (final r in rows) presentTx(r.data)]
      ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
  }

  // -------------------------------------------------------------- webhook

  /// Handles a provider webhook. Anything that is not authentic answers the
  /// same generic way (the caller learns nothing about why).
  Future<Map<String, Object?>> webhook(
    String providerId,
    String tenantId,
    List<int> rawBody,
    Map<String, String> headers,
  ) async {
    final provider = _providers[providerId];
    final cfg = RegExp(r'^[A-Za-z0-9_-]{6,60}$').hasMatch(tenantId)
        ? await _config(tenantId)
        : null;
    if (provider == null || cfg == null || cfg['provider'] != providerId) {
      throw const ApiException.unauthenticated('Not accepted.');
    }
    // Current credentials first, then the previous ones during rotation.
    ProviderEvent? event;
    for (final ref in [cfg['credentialRef'], cfg['previousCredentialRef']]) {
      final creds = ref == null ? null : _creds.resolve('$ref');
      if (creds == null) continue;
      try {
        event = provider.verifyWebhook(rawBody, headers, creds);
        break;
      } on InvalidWebhook {
        continue;
      }
    }
    if (event == null) {
      throw const ApiException.unauthenticated('Not accepted.');
    }
    final ent = await _s.d.entitlements.forTenant(tenantId);
    final sys = _system(tenantId, providerId, ent);
    return _handleEvent(sys, providerId, event);
  }

  Future<Map<String, Object?>> _handleEvent(
    TenantContext sys,
    String providerId,
    ProviderEvent e,
  ) async {
    final key = _hash('$providerId:${e.eventId}').substring(0, 32);
    final evPath = _s.path(sys, 'gateway_events', key);
    final now = _s.d.now;
    try {
      await _store.commit([
        CreateOp(evPath, {
          'provider': providerId,
          'type': e.type,
          'providerRef': e.providerRef,
          'status': 'received',
          'receivedAt': now,
        }),
      ]);
    } on AlreadyExistsException {
      final ex = await _store.get(evPath);
      if (ex?['status'] == 'processed') {
        return {'duplicate': true};
      }
      // received but not finished (crash/retry): resume safely
    }
    final rows = await _store.query(
      DocQuery(
        _s.path(sys, txCollection),
        filters: [
          QueryFilter('providerRef', FilterOp.eq, e.providerRef),
          QueryFilter('provider', FilterOp.eq, providerId),
        ],
        limit: 2,
      ),
    );
    Future<Map<String, Object?>> done(String outcome) async {
      await _store.commit([
        UpdateOp(evPath, {
          'status': 'processed',
          'outcome': outcome,
          'processedAt': _s.d.now,
        }),
      ]);
      return {'duplicate': false, 'outcome': outcome};
    }

    if (rows.length != 1) {
      await _exception(sys, key, 'unknown_transaction', null);
      return done('exception');
    }
    final tx = rows.first.data;
    final txPath = _s.path(sys, txCollection, '${tx['transactionId']}');
    final from = '${tx['status']}';

    Future<Map<String, Object?>> conflict(String type) async {
      await _exception(sys, key, type, tx['transactionId'] as String?);
      return done('exception');
    }

    Future<void> move(String to, [Map<String, Object?> extra = const {}]) =>
        _store.commit([
          UpdateOp(txPath, {
            'status': to,
            ...extra,
            'history': _trim([
              ...((tx['history'] as List?) ?? const []),
              {
                'at': _s.d.now,
                'event': e.type,
                'from': from,
                'to': to,
                'eventKey': key,
              },
            ]),
            'updatedAt': _s.d.now,
          }),
        ]);

    final settlementPatch = e.settlement == null
        ? const <String, Object?>{}
        : {
            'settlement': {
              'currency': e.settlement!.currency,
              'amountMinor': e.settlement!.amountMinor,
              'feeMinor': e.settlement!.feeMinor,
              'fxRate': e.settlement!.fxRate,
              'settledAt': e.settlement!.settledAt,
              'recordedAt': _s.d.now,
            },
          };

    switch (e.type) {
      case 'payment.authorized':
        if (from == 'authorized' || !openGatewayStatuses.contains(from)) {
          return done('ignored');
        }
        if (canMoveGateway(from, 'authorized')) {
          await move('authorized');
        }
        return done('applied');
      case 'payment.failed':
      case 'payment.cancelled':
        final to = e.type == 'payment.failed' ? 'failed' : 'cancelled';
        if (from == to) return done('ignored');
        if (!canMoveGateway(from, to)) return conflict('state_conflict');
        await move(to);
        return done('applied');
      case 'payment.captured':
        if (from == 'captured' ||
            from == 'partially_refunded' ||
            from == 'refunded' ||
            from == 'disputed') {
          return done('ignored'); // already captured under another event id
        }
        if (!canMoveGateway(from, 'captured')) return conflict('late_capture');
        if (e.amountMinor != tx['amountMinor']) {
          return conflict('amount_mismatch');
        }
        if (e.currency != tx['currency']) return conflict('currency_mismatch');
        final inv = await _store.get(
          _s.path(sys, InvoiceService.collection, '${tx['invoiceId']}'),
        );
        final due = InvoiceService.acceptsPayment(inv ?? const {})
            ? (inv!['outstanding']! as int)
            : 0;
        final amount = tx['amountMinor']! as int;
        final allocate = amount < due ? amount : due;
        Map<String, Object?> payment;
        try {
          payment = await _payments.create(
            sys,
            {
              'patientId': tx['patientId'],
              'branchId': tx['branchId'],
              'amountMinor': amount,
              'method': 'online',
              'reference': tx['providerRef'],
              if (allocate > 0)
                'allocations': [
                  {'invoiceId': tx['invoiceId'], 'amountMinor': allocate},
                ],
              if (allocate < amount) 'advance': true,
            },
            idempotencyKey: 'gw_${tx['transactionId']}',
            gateway: {
              'provider': providerId,
              'transactionId': tx['transactionId'],
              'providerRef': tx['providerRef'],
            },
          );
        } on Object {
          await _exception(
            sys,
            key,
            'payment_record_failed',
            tx['transactionId'] as String?,
          );
          rethrow; // 5xx: the provider redelivers; the event stays 'received'
        }
        await move('captured', {
          'paymentId': payment['paymentId'],
          'receiptNumber': payment['receiptNumber'],
          'capturedAt': _s.d.now,
          ...settlementPatch,
        });
        return done('applied');
      case 'settlement.updated':
        if (e.settlement == null ||
            !const {
              'captured',
              'partially_refunded',
              'refunded',
              'disputed',
            }.contains(from)) {
          return done('ignored');
        }
        await _store.commit([
          UpdateOp(txPath, {...settlementPatch, 'updatedAt': _s.d.now}),
        ]);
        return done('applied');
      case 'dispute.opened':
        if (!(_providers[providerId]?.capabilities.disputes ?? false)) {
          return done('ignored');
        }
        if (!canMoveGateway(from, 'disputed')) {
          return conflict('state_conflict');
        }
        await move('disputed', {'statusBeforeDispute': from});
        await _exception(
          sys,
          key,
          'dispute_opened',
          tx['transactionId'] as String?,
        );
        return done('applied');
      case 'dispute.closed':
        if (from != 'disputed') return done('ignored');
        await move(
          ((tx['refundedTotal'] as int?) ?? 0) > 0
              ? 'partially_refunded'
              : 'captured',
        );
        return done('applied');
      case 'refund.processed':
      case 'refund.failed':
        final ref = e.refundRef;
        final local = ref == null
            ? const <StoredDoc>[]
            : await _store.query(
                DocQuery(
                  _s.path(sys, 'refunds'),
                  filters: [QueryFilter('reference', FilterOp.eq, ref)],
                  limit: 2,
                ),
              );
        if (local.length != 1) return conflict('external_refund');
        final refund = local.first.data;
        if (refund['status'] == 'processing') {
          final ok = e.type == 'refund.processed';
          final res = await _refunds.complete(sys, '${refund['refundId']}', {
            'outcome': ok ? 'completed' : 'failed',
            'method': 'online',
            if (ok) 'reference': ref,
            if (!ok)
              'failureReason': 'The provider reported the refund failed.',
          }, viaGateway: true);
          if (ok && res['idempotentReplay'] != true) {
            await _addRefunded(sys, tx, refund['amount']! as int);
          }
        }
        return done('applied');
    }
    return done('ignored');
  }

  List<Object?> _trim(List<Object?> h) =>
      h.length > 40 ? h.sublist(h.length - 40) : h;

  Future<void> _addRefunded(
    TenantContext sys,
    Map<String, Object?> tx,
    int amount,
  ) async {
    final p = _s.path(sys, txCollection, '${tx['transactionId']}');
    await _store.transaction((db) async {
      final cur = await db.get(p);
      if (cur == null) return;
      final total = ((cur['refundedTotal'] as int?) ?? 0) + amount;
      final to = total >= (cur['amountMinor']! as int)
          ? 'refunded'
          : 'partially_refunded';
      final status = '${cur['status']}';
      db.write([
        UpdateOp(p, {
          'refundedTotal': total,
          if (status != 'disputed') 'status': to,
          'history': _trim([
            ...((cur['history'] as List?) ?? const []),
            {'at': _s.d.now, 'event': 'refund', 'from': status, 'to': to},
          ]),
          'updatedAt': _s.d.now,
        }),
      ]);
    });
  }

  Future<void> _exception(
    TenantContext sys,
    String eventKey,
    String type,
    String? transactionId,
  ) async {
    try {
      await _store.commit([
        CreateOp(_s.path(sys, 'gateway_exceptions', 'ex_${eventKey}_$type'), {
          'exceptionId': 'ex_${eventKey}_$type',
          'type': type,
          'transactionId': transactionId,
          'eventKey': eventKey,
          'status': 'open',
          'createdAt': _s.d.now,
        }),
      ]);
    } on AlreadyExistsException {
      // one exception per event and kind
    }
  }

  // ---------------------------------------------------------------- sync

  /// Asks the provider for the current status and applies it exactly like a
  /// webhook (same checks, same replay protection).
  Future<Map<String, Object?>> sync(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.gatewayReconcile);
    final tx = await _store.get(_s.path(t, txCollection, id));
    if (tx == null || !t.scope.allows('${tx['branchId']}')) {
      throw const ApiException.notFound('Transaction not found.');
    }
    final c = await _config(t.tenantId);
    final provider = _providers['${tx['provider']}'];
    final creds = c == null ? null : _creds.resolve('${c['credentialRef']}');
    final ref = tx['providerRef'] as String?;
    if (provider == null ||
        creds == null ||
        ref == null ||
        !provider.capabilities.inquiry) {
      throw const ApiException.conflict(
        'This transaction cannot be checked with the provider.',
      );
    }
    final ProviderStatus ps;
    try {
      ps = await provider.inquire(ref, creds);
    } on Object {
      throw const ApiException(
        ApiErrorCode.unavailable,
        'The payment provider is not available. Try again later.',
      );
    }
    const types = {
      'authorized': 'payment.authorized',
      'captured': 'payment.captured',
      'failed': 'payment.failed',
      'cancelled': 'payment.cancelled',
    };
    final type = types[ps.status];
    if (type != null && ps.status != tx['status']) {
      final ent = await _s.d.entitlements.forTenant(t.tenantId);
      await _handleEvent(
        _system(t.tenantId, '${tx['provider']}', ent),
        '${tx['provider']}',
        ProviderEvent(
          eventId: 'inq_${ref}_${ps.status}',
          type: type,
          providerRef: ref,
          amountMinor: ps.amountMinor,
          currency: ps.currency,
          settlement: ps.settlement,
        ),
      );
    }
    await _store.commit([
      _s.audit(
        t,
        action: 'gateway.synced',
        resourceType: 'gateway_transaction',
        resourceId: id,
        requestId: requestId,
      ),
    ]);
    return detail(t, id);
  }

  // -------------------------------------------------------------- refund

  /// Executes an approved refund of an online payment at the provider, then
  /// records the outcome through the normal refund workflow.
  Future<Map<String, Object?>> refund(
    TenantContext t,
    String refundId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.refundProcess);
    final refund = await _refunds.load(t, refundId);
    if (refund['status'] == 'completed' && refund['method'] == 'online') {
      return {...BillingSupport.present(refund), 'idempotentReplay': true};
    }
    if (!const {
      'approved',
      'processing',
      'failed',
    }.contains(refund['status'])) {
      throw ApiException.conflict(
        'A ${refund['status']} refund cannot be sent.',
      );
    }
    final rows = await _store.query(
      DocQuery(
        _s.path(t, txCollection),
        filters: [QueryFilter('paymentId', FilterOp.eq, refund['paymentId'])],
        limit: 2,
      ),
    );
    if (rows.length != 1) {
      throw const ApiException.conflict('This was not an online payment.');
    }
    final tx = rows.first.data;
    final amount = refund['amount']! as int;
    final provider = _providers['${tx['provider']}'];
    final c = await _config(t.tenantId);
    final creds = c == null ? null : _creds.resolve('${c['credentialRef']}');
    if (provider == null || creds == null || !provider.capabilities.refunds) {
      throw const ApiException.conflict(
        'This provider cannot refund right now.',
      );
    }
    if (amount < (tx['amountMinor']! as int) &&
        !provider.capabilities.partialRefunds) {
      throw const ApiException.conflict('This provider refunds in full only.');
    }
    if (((tx['refundedTotal'] as int?) ?? 0) + amount >
        (tx['amountMinor']! as int)) {
      throw const ApiException.conflict(
        'The refund is more than what remains of this payment.',
      );
    }
    ProviderRefundResult res;
    try {
      res = await provider.refund(
        ProviderRefundRequest(
          providerRef: '${tx['providerRef']}',
          amountMinor: amount,
          currency: '${tx['currency']}',
          idempotencyKey: refundId,
        ),
        creds,
      );
    } on Object {
      res = const ProviderRefundResult(
        outcome: 'failed',
        errorCode: 'provider_error',
      );
    }
    final outcome =
        const {'completed', 'processing', 'failed'}.contains(res.outcome)
        ? res.outcome
        : 'failed';
    final done = await _refunds.complete(
      t,
      refundId,
      {
        'outcome': outcome,
        'method': 'online',
        if (res.refundRef != null) 'reference': res.refundRef,
        if (outcome == 'failed')
          'failureReason': 'Provider declined (${res.errorCode ?? 'error'}).',
      },
      requestId: requestId,
      viaGateway: true,
    );
    if (outcome == 'completed' && done['idempotentReplay'] != true) {
      await _addRefunded(t, tx, amount);
    }
    return done;
  }

  // ------------------------------------------------------ reconciliation

  Future<Map<String, Object?>> reconciliation(TenantContext t) async {
    t.require(ClinicPermission.gatewayReconcile);
    final ex = await _store.query(
      DocQuery(
        _s.path(t, 'gateway_exceptions'),
        filters: [const QueryFilter('status', FilterOp.eq, 'open')],
        limit: 200,
      ),
    );
    final all = await _store.query(
      DocQuery(_s.path(t, txCollection), limit: 500),
    );
    final cutoff = _s.d.now.subtract(staleAfter);
    final stale = [
      for (final r in all)
        if (openGatewayStatuses.contains(r.data['status']) &&
            (r.data['createdAt']! as DateTime).isBefore(cutoff))
          presentTx(r.data),
    ];
    final counts = <String, int>{};
    for (final r in all) {
      counts['${r.data['status']}'] = (counts['${r.data['status']}'] ?? 0) + 1;
    }
    return {
      'exceptions': [for (final r in ex) BillingSupport.present(r.data)],
      'staleTransactions': stale,
      'counts': counts,
      'truncated': all.length >= 500,
      'definitions': {
        'exceptions':
            'Events that were verified but could not be applied safely (amount or currency mismatch, late capture, unknown transaction, unmatched refund, dispute).',
        'staleTransactions':
            'Online payments still open after ${staleAfter.inMinutes} minutes; check them with the provider.',
      },
    };
  }

  Future<Map<String, Object?>> resolveException(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.gatewayReconcile);
    final r = BodyReader(body)..rejectUnknown({'note'});
    final note = r.str('note', min: 5, max: 300);
    r.throwIfInvalid();
    final p = _s.path(t, 'gateway_exceptions', id);
    final cur = await _store.get(p);
    if (cur == null) throw const ApiException.notFound('Exception not found.');
    if (cur['status'] == 'resolved') {
      return BillingSupport.present(cur);
    }
    final patch = {
      'status': 'resolved',
      'resolvedBy': t.uid,
      'resolvedAt': _s.d.now,
      'resolutionNote': note,
    };
    await _store.commit([
      UpdateOp(p, patch),
      _s.audit(
        t,
        action: 'gateway.exception_resolved',
        resourceType: 'gateway_exception',
        resourceId: id,
        requestId: requestId,
        reason: note,
      ),
    ]);
    return BillingSupport.present({...cur, ...patch});
  }
}
