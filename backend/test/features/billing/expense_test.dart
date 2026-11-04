import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late BillingClinic k;
  late String cat;

  setUp(() async {
    h = PlatformHarness();
    k = BillingClinic(h);
    await k.init();
    cat =
        (await h.okData(
              h.call(
                'POST',
                '/expenses/categories',
                uid: 'owner',
                body: {'name': 'Rent'},
              ),
              status: 201,
            ))['categoryId']!
            as String;
  });

  Map<String, Object?> body({
    int amount = 500000,
    String? branch,
    Map<String, Object?>? extra,
  }) => {
    'categoryId': cat,
    'description': 'Monthly clinic rent',
    'amountMinor': amount,
    'expenseDate': '2026-06-01',
    'vendor': 'Landlord & Co',
    'branchId': ?branch,
    ...?extra,
  };

  Future<Map<String, Object?>> create({
    String uid = 'acct',
    Map<String, Object?>? b,
  }) => h.okData(
    h.call(
      'POST',
      '/expenses',
      uid: uid,
      body: b ?? body(branch: k.br),
    ),
    status: 201,
  );

  Future<int> act(
    String id,
    String action, {
    String uid = 'owner',
    Map<String, Object?>? b,
  }) => h.status('POST', '/expenses/$id/$action', uid: uid, body: b ?? {});

  group('categories', () {
    test('owner and admin configure them; names are unique', () async {
      expect(
        await h.status(
          'POST',
          '/expenses/categories',
          uid: 'owner',
          body: {'name': 'rent'},
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/expenses/categories',
          uid: 'acct',
          body: {'name': 'Salaries'},
        ),
        403,
      );
      expect(
        await h.status(
          'POST',
          '/expenses/categories',
          uid: 'admin',
          body: {'name': 'Electricity'},
        ),
        201,
      );
      final list = h.list(
        await h.call('GET', '/expenses/categories', uid: 'acct'),
      );
      expect(await list, hasLength(2));
    });

    test('an inactive category cannot take new expenses', () async {
      await h.okData(
        h.call(
          'PATCH',
          '/expenses/categories/$cat',
          uid: 'owner',
          body: {'status': 'inactive'},
        ),
      );
      expect(
        await h.status(
          'POST',
          '/expenses',
          uid: 'acct',
          body: body(branch: k.br),
        ),
        404,
      );
    });
  });

  group('lifecycle', () {
    test('draft → submitted → approved → paid, with history', () async {
      final e = await create();
      final id = e['expenseId']! as String;
      expect(e['status'], 'draft');
      expect(e['currency'], 'INR');
      expect(e['createdBy'], 'acct');
      expect(await act(id, 'submit', uid: 'acct'), 200);
      expect(
        await act(
          id,
          'approve',
          uid: 'admin',
          b: {'notes': 'Verified against agreement'},
        ),
        200,
      );
      expect(
        await act(
          id,
          'pay',
          uid: 'acct',
          b: {'method': 'bank_transfer', 'reference': 'NEFT-9981'},
        ),
        200,
      );
      final d = await h.okData(h.call('GET', '/expenses/$id', uid: 'acct'));
      expect(d['status'], 'paid');
      expect(d['approvedBy'], 'admin');
      expect(d['paidBy'], 'acct');
      expect(d['paidMethod'], 'bank_transfer');
      expect((d['history']! as List).map((x) => (x as Map)['status']), [
        'draft',
        'submitted',
        'approved',
        'paid',
      ]);
      expect(
        k.auditActions(),
        containsAll([
          'expense.created',
          'expense.submitted',
          'expense.approved',
          'expense.paid',
        ]),
      );
    });

    test('approved and paid expenses cannot be edited', () async {
      final e = await create();
      final id = e['expenseId']! as String;
      await act(id, 'submit', uid: 'acct');
      await act(id, 'approve', uid: 'admin');
      expect(
        await h.status(
          'PATCH',
          '/expenses/$id',
          uid: 'acct',
          body: {'amountMinor': 1},
        ),
        409,
      );
      expect(await act(id, 'submit', uid: 'acct'), 409);
      await act(id, 'pay', uid: 'acct', b: {'method': 'cash'});
      expect(
        await h.status(
          'PATCH',
          '/expenses/$id',
          uid: 'owner',
          body: {'amountMinor': 1},
        ),
        409,
      );
      expect(
        await act(id, 'reject', uid: 'owner', b: {'reason': 'Changed my mind'}),
        409,
      );
    });

    test(
      'rejection needs a reason; an edit returns the expense to draft',
      () async {
        final e = await create();
        final id = e['expenseId']! as String;
        await act(id, 'submit', uid: 'acct');
        expect(await act(id, 'reject', uid: 'admin', b: {}), 422);
        expect(
          await act(
            id,
            'reject',
            uid: 'admin',
            b: {'reason': 'Missing receipt'},
          ),
          200,
        );
        expect(await act(id, 'pay', uid: 'acct', b: {'method': 'cash'}), 409);
        final fixed = await h.okData(
          h.call(
            'PATCH',
            '/expenses/$id',
            uid: 'acct',
            body: {'receiptReference': 'RCPT-1', 'expectedRev': 3},
          ),
        );
        expect(fixed['status'], 'draft');
        expect(fixed['receiptReference'], 'RCPT-1');
      },
    );

    test('a draft cannot jump to approved or paid', () async {
      final e = await create();
      final id = e['expenseId']! as String;
      expect(await act(id, 'approve', uid: 'admin'), 409);
      expect(await act(id, 'pay', uid: 'acct', b: {'method': 'cash'}), 409);
    });

    test(
      'stale edits conflict and only the owner of a draft may edit it',
      () async {
        final e = await create();
        final id = e['expenseId']! as String;
        expect(
          await h.status(
            'PATCH',
            '/expenses/$id',
            uid: 'acct',
            body: {'description': 'Edited', 'expectedRev': 99},
          ),
          409,
        );
        h.member('acct2', k.tid, 'accountant');
        expect(
          await h.status(
            'PATCH',
            '/expenses/$id',
            uid: 'acct2',
            body: {'description': 'Edited'},
          ),
          403,
        );
        expect(
          await h.status(
            'PATCH',
            '/expenses/$id',
            uid: 'admin',
            body: {'description': 'Edited by admin'},
          ),
          200,
        );
      },
    );

    test('payment and submit are not available to the wrong people', () async {
      final e = await create();
      final id = e['expenseId']! as String;
      expect(
        await act(id, 'submit', uid: 'admin'),
        403,
        reason: 'only the creator submits',
      );
      await act(id, 'submit', uid: 'acct');
      await act(id, 'approve', uid: 'admin');
      expect(await act(id, 'pay', uid: 'recep', b: {'method': 'cash'}), 403);
      expect(await act(id, 'pay', uid: 'acct', b: {'method': 'razorpay'}), 422);
    });
  });

  group('approval policy', () {
    test('unauthorized roles cannot approve or reject', () async {
      final e = await create();
      final id = e['expenseId']! as String;
      await act(id, 'submit', uid: 'acct');
      for (final uid in ['acct', 'recep', 'nurse', 'docuser']) {
        expect(await act(id, 'approve', uid: uid), 403, reason: uid);
        expect(
          await act(id, 'reject', uid: uid, b: {'reason': 'No thanks'}),
          403,
          reason: uid,
        );
      }
    });

    test('self-approval is refused unless policy permits it', () async {
      final e = await h.okData(
        h.call(
          'POST',
          '/expenses',
          uid: 'owner',
          body: body(branch: k.br),
        ),
        status: 201,
      );
      final id = e['expenseId']! as String;
      await act(id, 'submit', uid: 'owner');
      expect(await act(id, 'approve', uid: 'owner'), 403);
      await h.okData(
        h.call(
          'PUT',
          '/billing/settings',
          uid: 'owner',
          body: {'allowSelfApproval': true},
        ),
      );
      expect(await act(id, 'approve', uid: 'owner'), 200);
    });

    test('approval limits per role are enforced', () async {
      await h.okData(
        h.call(
          'PUT',
          '/billing/settings',
          uid: 'owner',
          body: {
            'expenseApprovalLimits': {'clinic_admin': 100000},
          },
        ),
      );
      final big = await create(b: body(amount: 250000, branch: k.br));
      final small = await create(b: body(amount: 90000, branch: k.br));
      for (final e in [big, small]) {
        await act(e['expenseId']! as String, 'submit', uid: 'acct');
      }
      expect(
        await act(big['expenseId']! as String, 'approve', uid: 'admin'),
        403,
      );
      expect(
        await act(small['expenseId']! as String, 'approve', uid: 'admin'),
        200,
      );
      // no limit is set for the owner
      expect(
        await act(big['expenseId']! as String, 'approve', uid: 'owner'),
        200,
      );
    });
  });

  group('validation and isolation', () {
    test('input is validated and server fields are not accepted', () async {
      Future<int> post(Map<String, Object?> b) =>
          h.status('POST', '/expenses', uid: 'acct', body: b);
      expect(await post(body(amount: 0)), 422);
      expect(await post(body(extra: {'expenseDate': '2026-13-45'})), 422);
      expect(await post(body(extra: {'method': 'razorpay'})), 422);
      expect(await post(body(extra: {'status': 'approved'})), 422);
      expect(await post(body(extra: {'tenantId': 'x'})), 422);
      expect(await post(body(extra: {'createdBy': 'owner'})), 422);
      expect(await post(body(extra: {'approvedBy': 'owner'})), 422);
      expect(
        await h.status('POST', '/expenses', uid: 'recep', body: body()),
        403,
      );
      expect(await h.status('GET', '/expenses', uid: 'recep'), 403);
      expect(await h.status('GET', '/expenses'), 401);
    });

    test('other clinics see nothing', () async {
      final e = await create();
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status('GET', '/expenses/${e['expenseId']}', uid: 'ownerB'),
        404,
      );
      expect(
        await h.list(await h.call('GET', '/expenses', uid: 'ownerB')),
        isEmpty,
      );
      expect(
        await act(e['expenseId']! as String, 'approve', uid: 'ownerB'),
        404,
      );
    });

    test(
      'branch-scoped users see only their branch; clinic-wide needs all branches',
      () async {
        final br2 = await h.newBranch('owner', code: 'BR2');
        h.member(
          'acctB2',
          k.tid,
          'accountant',
          allBranches: false,
          branchIds: [br2],
        );
        final mine = await h.okData(
          h.call(
            'POST',
            '/expenses',
            uid: 'owner',
            body: body(branch: k.br),
          ),
          status: 201,
        );
        final theirs = await h.okData(
          h.call(
            'POST',
            '/expenses',
            uid: 'owner',
            body: body(branch: br2),
          ),
          status: 201,
        );
        final wide = await h.okData(
          h.call('POST', '/expenses', uid: 'owner', body: body()),
          status: 201,
        );
        final list = await h.list(
          await h.call('GET', '/expenses', uid: 'acctB2'),
        );
        expect(list.map((e) => (e! as Map)['expenseId']), [
          theirs['expenseId'],
        ]);
        expect(
          await h.status(
            'GET',
            '/expenses/${mine['expenseId']}',
            uid: 'acctB2',
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/expenses/${wide['expenseId']}',
            uid: 'acctB2',
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/expenses',
            uid: 'acctB2',
            body: body(branch: k.br),
          ),
          404,
        );
        expect(
          await h.status('POST', '/expenses', uid: 'acctB2', body: body()),
          403,
          reason: 'clinic-wide needs all-branch access',
        );
        expect(
          await h.list(await h.call('GET', '/expenses', uid: 'owner')),
          hasLength(3),
        );
      },
    );

    test('lists filter by status, category and date', () async {
      final a = await create();
      await create(
        b: body(extra: {'expenseDate': '2026-05-10'}, branch: k.br),
      );
      await act(a['expenseId']! as String, 'submit', uid: 'acct');
      Future<int> n(String q) async => (await h.list(
        await h.call('GET', '/expenses$q', uid: 'acct'),
      )).length;
      expect(await n(''), 2);
      expect(await n('?status=submitted'), 1);
      expect(await n('?from=2026-06-01'), 1);
      expect(await n('?to=2026-05-31'), 1);
      expect(await n('?categoryId=$cat'), 2);
      expect(await h.status('GET', '/expenses?status=bogus', uid: 'acct'), 400);
    });
  });
}
