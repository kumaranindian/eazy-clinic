import 'dart:convert';

import 'package:backend/features/compliance/compliance_core.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../support/platform_http_fixtures.dart';

const inEstablishment = 'in-clinical-establishment';
const facilityReq =
    'facility-registration'; // evidence required, expiry tracked
const inPrivacy = 'in-data-protection';
const privacyReq = 'privacy-notice-consent'; // evidence required, no expiry

PlatformHarness harness() {
  final h = PlatformHarness();
  h.user('root', role: PlatformRole.superAdmin);
  h.user('support', role: PlatformRole.platformSupportAdmin);
  return h;
}

String pdf([String extra = '']) =>
    base64Encode(utf8.encode('%PDF-1.4\n$extra\n%%EOF'));

Future<void> seed(PlatformHarness h) async {
  await h.okData(
    h.call('POST', '/platform/compliance/profiles/seed-baseline', uid: 'root'),
  );
}

Future<void> confirm(PlatformHarness h, String tid, String profile) async {
  await h.okData(
    h.call(
      'PUT',
      '/platform/tenants/$tid/compliance/applicability/$profile',
      uid: 'root',
      body: {'status': 'applies', 'reason': 'Confirmed with the clinic'},
    ),
  );
}

Future<Map<String, Object?>> upload(
  PlatformHarness h,
  String uid, {
  String profile = inEstablishment,
  String req = facilityReq,
  String? validTo = '2027-12-31',
  String? data,
}) => h.okData(
  h.call(
    'POST',
    '/compliance/evidence',
    uid: uid,
    body: {
      'profileKey': profile,
      'requirementKey': req,
      'kind': 'registration',
      'title': 'Registration certificate',
      'documentNumber': 'REG-123',
      'validTo': ?validTo,
      'contentType': 'application/pdf',
      'dataBase64': data ?? pdf(),
    },
  ),
  status: 201,
);

Future<Response> review(
  PlatformHarness h,
  String tid,
  String eid,
  Map<String, Object?> body, {
  String uid = 'root',
}) => h.call(
  'POST',
  '/platform/tenants/$tid/compliance/evidence/$eid/review',
  uid: uid,
  body: body,
);

Future<Map<String, Object?>> dash(PlatformHarness h, String uid) =>
    h.okData(h.call('GET', '/compliance/dashboard', uid: uid));

Future<Map<String, Object?>> pdash(PlatformHarness h, String tid) =>
    h.okData(h.call('GET', '/platform/tenants/$tid/compliance', uid: 'root'));

Map<String, Object?> profileOf(Map<String, Object?> d, String key) =>
    (d['profiles']! as List).cast<Map<String, Object?>>().firstWhere(
      (p) => p['key'] == key,
    );

Map<String, Object?> requirementOf(
  Map<String, Object?> d,
  String profile,
  String req,
) => (profileOf(d, profile)['requirements']! as List)
    .cast<Map<String, Object?>>()
    .firstWhere((r) => r['key'] == req);

void main() {
  group('profile administration', () {
    test(
      'seeding creates the registers once and never overwrites edits',
      () async {
        final h = harness();
        final first = await h.okData(
          h.call(
            'POST',
            '/platform/compliance/profiles/seed-baseline',
            uid: 'root',
          ),
        );
        expect(
          (first['items']! as List).every((e) => (e as Map)['created'] == true),
          isTrue,
        );
        expect((first['items']! as List).length, 8);
        h.store.docs['compliance_profiles/$inPrivacy']!['title'] =
            'Edited title';
        final second = await h.okData(
          h.call(
            'POST',
            '/platform/compliance/profiles/seed-baseline',
            uid: 'root',
          ),
        );
        expect(
          (second['items']! as List).every(
            (e) => (e as Map)['created'] == false,
          ),
          isTrue,
        );
        expect(
          h.store.docs['compliance_profiles/$inPrivacy']!['title'],
          'Edited title',
        );
      },
    );

    test('list, filter by country, read, versions', () async {
      final h = harness();
      await seed(h);
      final all =
          (await h.okData(
                h.call('GET', '/platform/compliance/profiles', uid: 'support'),
              ))['items']!
              as List;
      expect(all, hasLength(8));
      final ae =
          (await h.okData(
                h.call(
                  'GET',
                  '/platform/compliance/profiles?countryCode=AE',
                  uid: 'support',
                ),
              ))['items']!
              as List;
      expect(ae.map((e) => (e as Map)['countryCode']).toSet(), {'AE'});
      final p = await h.okData(
        h.call(
          'GET',
          '/platform/compliance/profiles/$inPrivacy',
          uid: 'support',
        ),
      );
      expect((p['legalReview']! as Map)['status'], 'pending');
      final v =
          (await h.okData(
                h.call(
                  'GET',
                  '/platform/compliance/profiles/$inPrivacy/versions',
                  uid: 'support',
                ),
              ))['items']!
              as List;
      expect(v, hasLength(1));
      expect(
        (await h.call(
          'GET',
          '/platform/compliance/profiles/nope-x',
          uid: 'support',
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'GET',
          '/platform/compliance/profiles/Bad_Key',
          uid: 'support',
        )).statusCode,
        404,
      );
    });

    test(
      'permissions: support reads, only super admin changes; strangers refused',
      () async {
        final h = harness();
        h.user('plain');
        await seed(h);
        for (final (m, p, b) in [
          ('POST', '/platform/compliance/profiles/seed-baseline', null),
          (
            'PATCH',
            '/platform/compliance/profiles/$inPrivacy',
            {'expectedVersion': 1, 'reason': 'x y z'},
          ),
        ]) {
          expect(
            (await h.call(m, p, uid: 'support', body: b)).statusCode,
            403,
            reason: p,
          );
          expect(
            (await h.call(m, p, uid: 'plain', body: b)).statusCode,
            403,
            reason: p,
          );
        }
        expect(
          (await h.call(
            'GET',
            '/platform/compliance/profiles',
            uid: 'plain',
          )).statusCode,
          403,
        );
        expect(
          (await h.call('GET', '/platform/compliance/profiles')).statusCode,
          401,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/compliance/review-queue',
            uid: 'support',
          )).statusCode,
          403,
        );
      },
    );

    test(
      'an update publishes a new version with a snapshot, reason and impact report',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inPrivacy);
        final p = (await h.okData(
          h.call(
            'GET',
            '/platform/compliance/profiles/$inPrivacy',
            uid: 'root',
          ),
        ));
        final reqs = (p['requirements']! as List).cast<Map<String, Object?>>();
        final changed = [
          for (final r in reqs)
            if (r['key'] == privacyReq)
              {...r, 'title': 'Privacy notice and consent (reworded)'}
            else
              r,
          {
            ...reqs.first,
            'key': 'new-requirement',
            'title': 'A new requirement',
          },
        ]..removeWhere((r) => r['key'] == 'children-guardian-consent');
        final updated = await h.okData(
          h.call(
            'PATCH',
            '/platform/compliance/profiles/$inPrivacy',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'Counsel feedback round 1',
              'requirements': changed,
            },
          ),
        );
        expect(updated['version'], 2);
        final impact = await h.okData(
          h.call(
            'GET',
            '/platform/compliance/profiles/$inPrivacy/impact',
            uid: 'support',
          ),
        );
        expect(impact['tenantsAffected'], 1);
        final change = impact['change']! as Map;
        expect(change['added'], ['new-requirement']);
        expect(change['removed'], ['children-guardian-consent']);
        expect(change['changed'], [privacyReq]);
        final versions =
            (await h.okData(
                  h.call(
                    'GET',
                    '/platform/compliance/profiles/$inPrivacy/versions',
                    uid: 'root',
                  ),
                ))['items']!
                as List;
        expect(versions.map((e) => (e as Map)['version']), [2, 1]);
        expect(
          h
              .store
              .docs['compliance_profiles/$inPrivacy/versions/1']!['requirements'],
          hasLength(reqs.length),
        );
      },
    );

    test(
      'stale versions conflict; a reason and the version are required; scope fields are fixed',
      () async {
        final h = harness();
        await seed(h);
        Future<int> patch(Map<String, Object?> b) async => (await h.call(
          'PATCH',
          '/platform/compliance/profiles/$inPrivacy',
          uid: 'root',
          body: b,
        )).statusCode;
        expect(
          await patch({'expectedVersion': 1, 'title': 'New title here'}),
          422,
        ); // no reason
        expect(
          await patch({'reason': 'because', 'title': 'New title here'}),
          422,
        ); // no version
        expect(
          await patch({
            'expectedVersion': 1,
            'reason': 'rename',
            'countryCode': 'AE',
          }),
          422,
        );
        expect(
          await patch({
            'expectedVersion': 1,
            'reason': 'rename',
            'key': 'other-key',
          }),
          422,
        );
        expect(
          await patch({
            'expectedVersion': 1,
            'reason': 'rename',
            'title': 'New title here',
          }),
          200,
        );
        expect(
          await patch({
            'expectedVersion': 1,
            'reason': 'stale',
            'title': 'Another title',
          }),
          409,
        );
      },
    );

    test(
      'invalid content is rejected: no source, high confidence without review, reviewed without reviewer',
      () async {
        final h = harness();
        await seed(h);
        final p = await h.okData(
          h.call(
            'GET',
            '/platform/compliance/profiles/$inPrivacy',
            uid: 'root',
          ),
        );
        final reqs = (p['requirements']! as List).cast<Map<String, Object?>>();
        Future<Response> patch(Map<String, Object?> body) => h.call(
          'PATCH',
          '/platform/compliance/profiles/$inPrivacy',
          uid: 'root',
          body: {'expectedVersion': 1, 'reason': 'test change', ...body},
        );
        var r = await patch({
          'requirements': [
            {
              ...reqs.first,
              'source': {'reference': ''},
            },
          ],
        });
        expect(r.statusCode, 422);
        r = await patch({
          'requirements': [
            {...reqs.first, 'confidence': 'high'},
          ],
        });
        expect(r.statusCode, 422);
        r = await patch({
          'legalReview': {'status': 'reviewed'},
        });
        expect(r.statusCode, 422);
        r = await patch({
          'requirements': [reqs.first, reqs.first],
        });
        expect(r.statusCode, 422);
        r = await patch({'requirements': <Object?>[]});
        expect(r.statusCode, 422);
        expect(h.store.docs['compliance_profiles/$inPrivacy']!['version'], 1);
      },
    );

    test(
      'a profile can be marked legally reviewed only with reviewer and date; every change is audited',
      () async {
        final h = harness();
        await seed(h);
        await h.okData(
          h.call(
            'PATCH',
            '/platform/compliance/profiles/$inPrivacy',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'Counsel sign-off recorded',
              'legalReview': {
                'status': 'reviewed',
                'reviewedBy': 'Counsel A',
                'reviewedOn': '2026-12-01',
                'notes': 'ok',
              },
            },
          ),
        );
        final audits = h.store.docs.values.where(
          (d) => d['action'] == 'compliance_profile.updated',
        );
        expect(audits, hasLength(1));
        expect(audits.single['reason'], 'Counsel sign-off recorded');
      },
    );
  });

  group('applicability', () {
    test(
      'nothing applies by default; the clinic sees an honest empty state',
      () async {
        final h = harness();
        await seed(h);
        await h.createClinic('owner1');
        final d = await dash(h, 'owner1');
        expect(d['readiness'], 'applicability_unconfirmed');
        expect(d['countryCode'], 'IN');
        final p = profileOf(d, inPrivacy);
        expect((p['applicability']! as Map)['status'], 'unknown');
        expect(p['requirements'], isEmpty);
        expect(d['disclaimer'], contains('not legal advice'));
      },
    );

    test(
      'a reviewer confirms applicability; requirements then start as not assessed',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inPrivacy);
        final d = await dash(h, 'owner1');
        final reqs = (profileOf(d, inPrivacy)['requirements']! as List)
            .cast<Map<String, Object?>>();
        expect(reqs, isNotEmpty);
        expect(reqs.every((r) => r['status'] == 'not_assessed'), isTrue);
        expect(
          d['readiness'],
          'awaiting_legal_validation',
        ); // drafts are not validated
      },
    );

    test(
      'a profile of another country cannot be applied to a clinic',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        final r = await h.call(
          'PUT',
          '/platform/tenants/$tid/compliance/applicability/ae-dha-dubai',
          uid: 'root',
          body: {'status': 'applies', 'reason': 'wrong country'},
        );
        expect(r.statusCode, 409);
        expect(
          (await h.call(
            'PUT',
            '/platform/tenants/$tid/compliance/applicability/missing-profile',
            uid: 'root',
            body: {'status': 'applies', 'reason': 'x y z'},
          )).statusCode,
          404,
        );
      },
    );

    test(
      'clinic users, support admins and strangers cannot set applicability',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        h.user('plain');
        for (final uid in ['owner1', 'support', 'plain']) {
          final r = await h.call(
            'PUT',
            '/platform/tenants/$tid/compliance/applicability/$inPrivacy',
            uid: uid,
            body: {'status': 'applies', 'reason': 'self service'},
          );
          expect(r.statusCode, 403, reason: uid);
        }
        expect(
          h.store.docs.keys.where(
            (k) => k.contains('compliance_applicability'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'a clinic in the UAE gets UAE profiles only, and a clinic without a country gets none',
      () async {
        final h = harness();
        await seed(h);
        await h.createClinic(
          'ae',
          name: 'Dubai Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final d = await dash(h, 'ae');
        expect(
          (d['profiles']! as List).map((p) => (p as Map)['key']).toSet(),
          containsAll([
            'ae-dha-dubai',
            'ae-doh-abu-dhabi',
            'ae-mohap-northern-emirates',
            'ae-health-data-privacy',
          ]),
        );
        expect(
          (d['profiles']! as List).any(
            (p) => (p as Map)['key'].toString().startsWith('in-'),
          ),
          isFalse,
        );

        final tid = await h.createClinic('legacy', name: 'Old Clinic');
        h.store.docs['tenants/$tid']!.remove('countryCode');
        final legacy = await dash(h, 'legacy');
        expect(legacy['readiness'], 'country_not_assigned');
        expect(legacy['profiles'], isEmpty);
      },
    );
  });

  group('evidence workflow', () {
    test('upload needs confirmed applicability', () async {
      final h = harness();
      await seed(h);
      await h.createClinic('owner1');
      final r = await h.call(
        'POST',
        '/compliance/evidence',
        uid: 'owner1',
        body: {
          'profileKey': inEstablishment,
          'requirementKey': facilityReq,
          'kind': 'registration',
          'title': 'Registration',
          'validTo': '2027-12-31',
          'dataBase64': pdf(),
        },
      );
      expect(r.statusCode, 409);
    });

    test(
      'upload moves the requirement to under review and keeps the file private',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inEstablishment);
        final e = await upload(h, 'owner1');
        expect(e['status'], 'submitted');
        expect(e.containsKey('storagePath'), isFalse);
        expect(e.containsKey('sha256'), isFalse);
        final d = await dash(h, 'owner1');
        expect(
          requirementOf(d, inEstablishment, facilityReq)['status'],
          'under_review',
        );
        expect(
          h.storage.objects.keys.single,
          startsWith('tenants/$tid/compliance/'),
        );
      },
    );

    test('files are checked by their bytes, size and encoding', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      Future<int> code(String data) async => (await h.call(
        'POST',
        '/compliance/evidence',
        uid: 'owner1',
        body: {
          'profileKey': inEstablishment,
          'requirementKey': facilityReq,
          'kind': 'license',
          'title': 'Doc',
          'validTo': '2027-12-31',
          'contentType': 'application/pdf',
          'dataBase64': data,
        },
      )).statusCode;
      expect(
        await code(
          base64Encode(utf8.encode('<html><script>alert(1)</script>')),
        ),
        422,
      );
      expect(await code(base64Encode(utf8.encode('MZ\u0090 not a pdf'))), 422);
      expect(await code('not base64!!'), 422);
      expect(await code(''), 422);
      expect(
        await code(
          base64Encode([
            0x25,
            0x50,
            0x44,
            0x46,
            ...List.filled(maxEvidenceBytes, 1),
          ]),
        ),
        anyOf(413, 422),
      );
      expect(h.storage.objects, isEmpty);
    });

    test('expiry-tracked requirements need a future end date', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      Future<int> code(String? validTo) async => (await h.call(
        'POST',
        '/compliance/evidence',
        uid: 'owner1',
        body: {
          'profileKey': inEstablishment,
          'requirementKey': facilityReq,
          'kind': 'license',
          'title': 'Doc',
          'validTo': ?validTo,
          'dataBase64': pdf(),
        },
      )).statusCode;
      expect(await code(null), 422);
      expect(await code('2020-01-01'), 422);
      expect(await code('31/12/2027'), 422);
      expect(await code('2027-12-31'), 201);
    });

    test(
      'unknown profile or requirement; unsupported kinds and fields',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inEstablishment);
        Future<int> code(Map<String, Object?> patch) async => (await h.call(
          'POST',
          '/compliance/evidence',
          uid: 'owner1',
          body: {
            'profileKey': inEstablishment,
            'requirementKey': facilityReq,
            'kind': 'license',
            'title': 'Doc',
            'validTo': '2027-12-31',
            'dataBase64': pdf(),
            ...patch,
          },
        )).statusCode;
        expect(await code({'requirementKey': 'no-such-req'}), 404);
        expect(await code({'profileKey': 'no-such-profile'}), 404);
        expect(await code({'kind': 'selfie'}), 422);
        expect(await code({'tenantId': 'ten_other'}), 422);
        expect(await code({'status': 'approved'}), 422);
      },
    );

    test('a clinic cannot approve its own evidence, even as owner', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      final e = await upload(h, 'owner1');
      final eid = e['evidenceId']! as String;
      expect(
        (await review(h, tid, eid, {
          'decision': 'accept',
        }, uid: 'owner1')).statusCode,
        403,
      );
      expect(
        (await review(h, tid, eid, {
          'decision': 'accept',
        }, uid: 'support')).statusCode,
        403,
      );
      expect(
        requirementOf(
          await dash(h, 'owner1'),
          inEstablishment,
          facilityReq,
        )['status'],
        'under_review',
      );
    });

    test(
      'accepting evidence approves the requirement and starts the expiry clock',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inEstablishment);
        final eid =
            (await upload(h, 'owner1', validTo: '2026-09-30'))['evidenceId']!
                as String;
        final r = await h.okData(
          review(h, tid, eid, {
            'decision': 'accept',
            'note': 'Checked against the original',
          }),
        );
        expect(r['requirementStatus'], 'approved');
        final req = requirementOf(
          await dash(h, 'owner1'),
          inEstablishment,
          facilityReq,
        );
        expect(req['status'], 'approved');
        expect(req['expiresAt'], startsWith('2026-09-30'));
        expect(req['reviewedBy'], 'root');
        // the same evidence cannot be reviewed twice
        expect(
          (await review(h, tid, eid, {
            'decision': 'reject',
            'note': 'changed my mind',
          })).statusCode,
          409,
        );
      },
    );

    test('rejecting needs a reason; the clinic can resubmit', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      final eid = (await upload(h, 'owner1'))['evidenceId']! as String;
      expect(
        (await review(h, tid, eid, {'decision': 'reject'})).statusCode,
        422,
      );
      await h.okData(
        review(h, tid, eid, {
          'decision': 'reject',
          'note': 'Certificate is unreadable',
        }),
      );
      expect(
        requirementOf(
          await dash(h, 'owner1'),
          inEstablishment,
          facilityReq,
        )['status'],
        'rejected',
      );
      final second = await upload(h, 'owner1', data: pdf('second scan'));
      expect(
        requirementOf(
          await dash(h, 'owner1'),
          inEstablishment,
          facilityReq,
        )['status'],
        'under_review',
      );
      final evidence =
          (await h.okData(
                h.call('GET', '/compliance/evidence', uid: 'owner1'),
              ))['items']!
              as List;
      expect(evidence.map((e) => (e as Map)['status']).toSet(), {
        'rejected',
        'submitted',
      });
      expect(second['status'], 'submitted');
    });

    test(
      'a newer upload supersedes the previous file and voids an approval until re-reviewed',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inEstablishment);
        final first = (await upload(h, 'owner1'))['evidenceId']! as String;
        await h.okData(review(h, tid, first, {'decision': 'accept'}));
        expect(
          requirementOf(
            await dash(h, 'owner1'),
            inEstablishment,
            facilityReq,
          )['status'],
          'approved',
        );
        await upload(h, 'owner1', data: pdf('renewed'));
        expect(
          requirementOf(
            await dash(h, 'owner1'),
            inEstablishment,
            facilityReq,
          )['status'],
          'under_review',
        );
        expect(
          h.store.docs['tenants/$tid/compliance_evidence/$first']!['status'],
          'superseded',
        );
      },
    );

    test(
      'marking not applicable needs a reviewer and a reason, and blocks uploads',
      () async {
        final h = harness();
        await seed(h);
        final tid = await h.createClinic('owner1');
        await confirm(h, tid, inEstablishment);
        final path =
            '/platform/tenants/$tid/compliance/items/$inEstablishment/$facilityReq/status';
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'owner1',
            body: {'status': 'not_applicable', 'reason': 'self'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'root',
            body: {'status': 'not_applicable'},
          )).statusCode,
          422,
        );
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'root',
            body: {'status': 'approved', 'reason': 'sneaky'},
          )).statusCode,
          422,
        );
        await h.okData(
          h.call(
            'POST',
            path,
            uid: 'root',
            body: {
              'status': 'not_applicable',
              'reason': 'Clinic is exempt in this state',
            },
          ),
        );
        expect(
          requirementOf(
            await dash(h, 'owner1'),
            inEstablishment,
            facilityReq,
          )['status'],
          'not_applicable',
        );
        final r = await h.call(
          'POST',
          '/compliance/evidence',
          uid: 'owner1',
          body: {
            'profileKey': inEstablishment,
            'requirementKey': facilityReq,
            'kind': 'license',
            'title': 'Doc',
            'validTo': '2027-12-31',
            'dataBase64': pdf(),
          },
        );
        expect(r.statusCode, 409);
        // a reviewer can reopen it
        await h.okData(
          h.call(
            'POST',
            path,
            uid: 'root',
            body: {
              'status': 'pending_evidence',
              'reason': 'Exemption withdrawn',
            },
          ),
        );
        expect(
          requirementOf(
            await dash(h, 'owner1'),
            inEstablishment,
            facilityReq,
          )['status'],
          'pending_evidence',
        );
      },
    );

    test(
      'downloads are tenant-scoped, audited and never use the document title as a file name',
      () async {
        final h = harness();
        await seed(h);
        final a = await h.createClinic('owner-a');
        final b = await h.createClinic('owner-b', name: 'B Clinic');
        await confirm(h, a, inEstablishment);
        final eid = (await upload(h, 'owner-a'))['evidenceId']! as String;

        final ok = await h.call(
          'GET',
          '/compliance/evidence/$eid/file',
          uid: 'owner-a',
        );
        expect(ok.statusCode, 200);
        expect(ok.headers['content-type'], 'application/pdf');
        expect(
          ok.headers['content-disposition'],
          'attachment; filename="evidence-$eid.pdf"',
        );
        expect(ok.headers['cache-control'], contains('no-store'));
        expect(ok.headers['x-content-type-options'], 'nosniff');
        expect((await ok.read().expand((x) => x).toList()).take(4), [
          0x25,
          0x50,
          0x44,
          0x46,
        ]);

        // another clinic cannot reach it, with its own or the other clinic's id
        expect(
          (await h.call(
            'GET',
            '/compliance/evidence/$eid/file',
            uid: 'owner-b',
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'GET',
            '/compliance/evidence/$eid/file',
            uid: 'owner-b',
            headers: {'x-tenant-id': a},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/tenants/$b/compliance/evidence/$eid/file',
            uid: 'root',
          )).statusCode,
          404,
        );

        // reviewers can read it; support admins cannot
        expect(
          (await h.call(
            'GET',
            '/platform/tenants/$a/compliance/evidence/$eid/file',
            uid: 'root',
          )).statusCode,
          200,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/tenants/$a/compliance/evidence/$eid/file',
            uid: 'support',
          )).statusCode,
          403,
        );

        final history =
            (await h.okData(
                  h.call('GET', '/compliance/history', uid: 'owner-a'),
                ))['items']!
                as List;
        expect(
          history.where((x) => (x as Map)['type'] == 'evidence_viewed'),
          hasLength(2),
        );
        expect(
          h.store.docs.values.where(
            (d) => d['action'] == 'compliance.evidence_viewed',
          ),
          hasLength(2),
        );
      },
    );

    test(
      'the review queue lists waiting evidence from every clinic for reviewers only',
      () async {
        final h = harness();
        await seed(h);
        final a = await h.createClinic('owner-a');
        final b = await h.createClinic('owner-b', name: 'B Clinic');
        await confirm(h, a, inEstablishment);
        await confirm(h, b, inEstablishment);
        await upload(h, 'owner-a');
        h.clock.now = h.clock.now.add(const Duration(minutes: 5));
        await upload(h, 'owner-b');
        final q =
            (await h.okData(
                  h.call(
                    'GET',
                    '/platform/compliance/review-queue',
                    uid: 'root',
                  ),
                ))['items']!
                as List;
        expect(q.map((e) => (e as Map)['tenantId']), [a, b]); // oldest first
        expect((q.first as Map).containsKey('storagePath'), isFalse);
        final overview = await h.okData(
          h.call('GET', '/platform/compliance/overview', uid: 'support'),
        );
        expect(overview['evidenceAwaitingReview'], 2);
        expect(overview['confirmedApplicabilities'], 2);
        expect(overview['profilesAwaitingLegalValidation'], 8);
      },
    );
  });

  group('no false compliance badge', () {
    Future<(PlatformHarness, String)> readyClinic() async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      return (h, tid);
    }

    Future<void> approveAll(PlatformHarness h, String tid) async {
      final d = await dash(h, 'owner1');
      for (final r
          in (profileOf(d, inEstablishment)['requirements']! as List)
              .cast<Map<String, Object?>>()) {
        final ev = r['evidence']! as Map;
        if (ev['required'] != true) continue;
        final e = await upload(
          h,
          'owner1',
          req: '${r['key']}',
          validTo: ev['expiryTracked'] == true ? '2027-12-31' : null,
        );
        await h.okData(
          review(h, tid, e['evidenceId']! as String, {'decision': 'accept'}),
        );
      }
    }

    test(
      'even with every requirement approved, an unvalidated register is not "ready"',
      () async {
        final (h, tid) = await readyClinic();
        await approveAll(h, tid);
        final d = await dash(h, 'owner1');
        expect(d['readiness'], 'awaiting_legal_validation');
        expect((d['counts']! as Map)['approved'], greaterThan(0));
      },
    );

    test(
      'readiness reaches "all required evidence approved" only after legal validation, and never says compliant',
      () async {
        final (h, tid) = await readyClinic();
        await approveAll(h, tid);
        await h.okData(
          h.call(
            'PATCH',
            '/platform/compliance/profiles/$inEstablishment',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'Counsel validated',
              'legalReview': {
                'status': 'reviewed',
                'reviewedBy': 'Counsel A',
                'reviewedOn': '2026-12-01',
              },
            },
          ),
        );
        final d = await dash(h, 'owner1');
        expect(d['readiness'], 'all_required_evidence_approved');
        expect(jsonEncode(d).toLowerCase(), isNot(contains('"compliant"')));
        expect(jsonEncode(d), contains('not legal advice'));
      },
    );

    test(
      'an approval stops counting when the requirement it approved changes',
      () async {
        final (h, tid) = await readyClinic();
        final e = await upload(h, 'owner1');
        await h.okData(
          review(h, tid, e['evidenceId']! as String, {'decision': 'accept'}),
        );
        final p = await h.okData(
          h.call(
            'GET',
            '/platform/compliance/profiles/$inEstablishment',
            uid: 'root',
          ),
        );
        final reqs = (p['requirements']! as List).cast<Map<String, Object?>>();
        await h.okData(
          h.call(
            'PATCH',
            '/platform/compliance/profiles/$inEstablishment',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'Rules changed',
              'requirements': [
                for (final r in reqs)
                  if (r['key'] == facilityReq)
                    {...r, 'description': 'New, stricter wording'}
                  else
                    r,
              ],
            },
          ),
        );
        final req = requirementOf(
          await dash(h, 'owner1'),
          inEstablishment,
          facilityReq,
        );
        expect(req['status'], 'pending_evidence');
        expect(req['requirementChanged'], isTrue);
      },
    );

    test(
      'an expired approval shows as expired immediately, with no job running',
      () async {
        final (h, tid) = await readyClinic();
        final e = await upload(h, 'owner1', validTo: '2026-09-30');
        await h.okData(
          review(h, tid, e['evidenceId']! as String, {'decision': 'accept'}),
        );
        expect(
          requirementOf(
            await dash(h, 'owner1'),
            inEstablishment,
            facilityReq,
          )['status'],
          'approved',
        );
        h.clock.now = DateTime.utc(2026, 10, 1);
        expect(
          requirementOf(
            await pdash(h, tid),
            inEstablishment,
            facilityReq,
          )['status'],
          'expired',
        );
        expect(
          h
              .store
              .docs['tenants/$tid/compliance_items/${inEstablishment}__$facilityReq']!['status'],
          'approved',
          reason: 'stored value untouched until the scan persists it',
        );
      },
    );

    test(
      'an approval of evidence with no future expiry cannot be granted',
      () async {
        final (h, tid) = await readyClinic();
        final e = await upload(h, 'owner1', validTo: '2026-12-31');
        h.clock.now = DateTime.utc(
          2027,
          2,
          1,
        ); // the document expired while waiting for review
        final r = await review(h, tid, e['evidenceId']! as String, {
          'decision': 'accept',
        });
        expect(r.statusCode, 409);
        expect(
          requirementOf(
            await pdash(h, tid),
            inEstablishment,
            facilityReq,
          )['status'],
          'under_review',
        );
      },
    );
  });

  group('credentials', () {
    Map<String, Object?> facility({
      String? validTo = '2027-01-31',
      String number = 'FAC-001',
    }) => {
      'subjectType': 'facility',
      'subjectName': 'Green Valley Clinic',
      'kind': 'facility_license',
      'authorityCode': 'DHA',
      'authorityName': 'Dubai Health Authority',
      'jurisdiction': 'dubai',
      'number': number,
      'issuedOn': '2025-02-01',
      'validFrom': '2025-02-01',
      'validTo': ?validTo,
    };

    test(
      'a clinic can record facility and practitioner credentials with validity states',
      () async {
        final h = harness();
        final tid = await h.createClinic('owner1');
        h.store.docs['tenants/$tid/doctors/doc_1'] = {
          'doctorId': 'doc_1',
          'status': 'active',
        };
        await h.okData(
          h.call(
            'POST',
            '/compliance/credentials',
            uid: 'owner1',
            body: facility(),
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/compliance/credentials',
            uid: 'owner1',
            body: {
              'subjectType': 'practitioner',
              'subjectName': 'Dr Asha Rao',
              'doctorId': 'doc_1',
              'kind': 'practitioner_registration',
              'authorityCode': 'NMC',
              'authorityName': 'State Medical Council',
              'number': 'MH/2020/1234',
              'validTo': '2026-07-15',
            },
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/compliance/credentials',
            uid: 'owner1',
            body: {
              'subjectType': 'practitioner',
              'subjectName': 'Dr Old',
              'kind': 'practitioner_license',
              'authorityCode': 'DHA',
              'authorityName': 'DHA',
              'number': 'OLD-1',
              'validTo': '2026-05-01',
            },
          ),
          status: 201,
        );
        final list =
            (await h.okData(
                  h.call('GET', '/compliance/credentials', uid: 'owner1'),
                ))['items']!
                as List;
        final byName = {
          for (final c in list.cast<Map<String, Object?>>())
            c['subjectName']: c,
        };
        expect(byName['Green Valley Clinic']!['validity'], 'valid');
        expect(byName['Dr Asha Rao']!['validity'], 'expiring');
        expect(byName['Dr Old']!['validity'], 'expired');
        expect(byName['Dr Asha Rao']!['daysToExpiry'], lessThan(60));
        final summary = (await dash(h, 'owner1'))['credentials']! as Map;
        expect(
          [summary['valid'], summary['expiring'], summary['expired']],
          [1, 1, 1],
        );
        expect(
          (summary['attention']! as List)
              .map((x) => (x as Map)['subjectName'])
              .toSet(),
          {'Dr Asha Rao', 'Dr Old'},
        );
      },
    );

    test(
      'validation: practitioner must exist, facility has none, formats and dates',
      () async {
        final h = harness();
        await h.createClinic('owner1');
        Future<int> code(Map<String, Object?> b) async => (await h.call(
          'POST',
          '/compliance/credentials',
          uid: 'owner1',
          body: b,
        )).statusCode;
        expect(
          await code({...facility(), 'doctorId': 'doc_x'}),
          422,
        ); // facility with doctor
        expect(
          await code({
            ...facility(),
            'subjectType': 'practitioner',
            'doctorId': 'doc_missing',
          }),
          422,
        );
        expect(await code({...facility(), 'number': '<script>'}), 422);
        expect(
          await code({
            ...facility(),
            'validTo': '2020-01-01',
            'validFrom': '2025-02-01',
          }),
          422,
        );
        expect(await code({...facility(), 'validTo': '31-01-2027'}), 422);
        expect(await code({...facility(), 'kind': 'driving_licence'}), 422);
        expect(await code({...facility(), 'tenantId': 'ten_x'}), 422);
        expect(
          await code({
            ...facility(),
            'verification': {'status': 'verified'},
          }),
          422,
        );
      },
    );

    test(
      'only a reviewer verifies, only with a document and an end date',
      () async {
        final h = harness();
        final tid = await h.createClinic('owner1');
        final c = await h.okData(
          h.call(
            'POST',
            '/compliance/credentials',
            uid: 'owner1',
            body: facility(),
          ),
          status: 201,
        );
        final id = c['credentialId']! as String;
        final path = '/platform/tenants/$tid/compliance/credentials/$id/verify';
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'root',
            body: {'decision': 'verify'},
          )).statusCode,
          409,
        ); // no document yet
        await h.okData(
          h.call(
            'POST',
            '/compliance/credentials/$id/document',
            uid: 'owner1',
            body: {'dataBase64': pdf('licence')},
          ),
        );
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'owner1',
            body: {'decision': 'verify'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'support',
            body: {'decision': 'verify'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'POST',
            path,
            uid: 'root',
            body: {'decision': 'reject'},
          )).statusCode,
          422,
        );
        final v = await h.okData(
          h.call(
            'POST',
            path,
            uid: 'root',
            body: {'decision': 'verify', 'note': 'Matches the register'},
          ),
        );
        expect((v['verification']! as Map)['status'], 'verified');
        expect(v['verifiedAndValid'], isTrue);
      },
    );

    test('changing what was verified voids the verification', () async {
      final h = harness();
      final tid = await h.createClinic('owner1');
      final id =
          (await h.okData(
                h.call(
                  'POST',
                  '/compliance/credentials',
                  uid: 'owner1',
                  body: facility(),
                ),
                status: 201,
              ))['credentialId']!
              as String;
      final verify = '/platform/tenants/$tid/compliance/credentials/$id/verify';
      Future<Map<String, Object?>> attach(String extra) => h.okData(
        h.call(
          'POST',
          '/compliance/credentials/$id/document',
          uid: 'owner1',
          body: {'dataBase64': pdf(extra)},
        ),
      );
      await attach('first');
      await h.okData(
        h.call('POST', verify, uid: 'root', body: {'decision': 'verify'}),
      );
      // a harmless note keeps the verification
      var c = await h.okData(
        h.call(
          'PATCH',
          '/compliance/credentials/$id',
          uid: 'owner1',
          body: {'notes': 'Filed in cabinet 2'},
        ),
      );
      expect((c['verification']! as Map)['status'], 'verified');
      // a new end date voids it, and it cannot be verified again without a new document
      c = await h.okData(
        h.call(
          'PATCH',
          '/compliance/credentials/$id',
          uid: 'owner1',
          body: {'validTo': '2030-01-31'},
        ),
      );
      expect((c['verification']! as Map)['status'], 'unverified');
      expect(c['verifiedAndValid'], isFalse);
      expect(
        (await h.call(
          'POST',
          verify,
          uid: 'root',
          body: {'decision': 'verify'},
        )).statusCode,
        409,
      );
      // attaching a document makes it reviewable again; a newer document voids the result again
      await attach('second');
      c = await h.okData(
        h.call('POST', verify, uid: 'root', body: {'decision': 'verify'}),
      );
      expect((c['verification']! as Map)['status'], 'verified');
      c = await attach('third');
      expect((c['verification']! as Map)['status'], 'unverified');
    });

    test('a verified credential stops counting once it expires', () async {
      final h = harness();
      final tid = await h.createClinic('owner1');
      final id =
          (await h.okData(
                h.call(
                  'POST',
                  '/compliance/credentials',
                  uid: 'owner1',
                  body: facility(validTo: '2026-08-31'),
                ),
                status: 201,
              ))['credentialId']!
              as String;
      await h.okData(
        h.call(
          'POST',
          '/compliance/credentials/$id/document',
          uid: 'owner1',
          body: {'dataBase64': pdf()},
        ),
      );
      await h.okData(
        h.call(
          'POST',
          '/platform/tenants/$tid/compliance/credentials/$id/verify',
          uid: 'root',
          body: {'decision': 'verify'},
        ),
      );
      Future<List<Object?>> list() async =>
          (await h.okData(
                h.call(
                  'GET',
                  '/platform/tenants/$tid/compliance/credentials',
                  uid: 'root',
                ),
              ))['items']!
              as List<Object?>;
      expect(((await list()).single! as Map)['verifiedAndValid'], isTrue);
      // (the clinic's own trial has lapsed by then, so ask as a reviewer)
      h.clock.now = DateTime.utc(2026, 9, 2);
      final after = (await list()).single! as Map;
      expect(after['validity'], 'expired');
      expect(after['verifiedAndValid'], isFalse);
    });

    test('archived credentials are hidden and cannot be edited', () async {
      final h = harness();
      await h.createClinic('owner1');
      final id =
          (await h.okData(
                h.call(
                  'POST',
                  '/compliance/credentials',
                  uid: 'owner1',
                  body: facility(),
                ),
                status: 201,
              ))['credentialId']!
              as String;
      await h.okData(
        h.call('POST', '/compliance/credentials/$id/archive', uid: 'owner1'),
      );
      expect(
        ((await h.okData(
              h.call('GET', '/compliance/credentials', uid: 'owner1'),
            ))['items']!
            as List),
        isEmpty,
      );
      expect(
        (await h.call(
          'PATCH',
          '/compliance/credentials/$id',
          uid: 'owner1',
          body: {'notes': 'x'},
        )).statusCode,
        409,
      );
      expect(
        (await h.call(
          'POST',
          '/compliance/credentials/$id/document',
          uid: 'owner1',
          body: {'dataBase64': pdf()},
        )).statusCode,
        409,
      );
    });

    test('another clinic cannot see or edit these credentials', () async {
      final h = harness();
      await h.createClinic('owner-a');
      await h.createClinic('owner-b', name: 'B Clinic');
      final id =
          (await h.okData(
                h.call(
                  'POST',
                  '/compliance/credentials',
                  uid: 'owner-a',
                  body: facility(),
                ),
                status: 201,
              ))['credentialId']!
              as String;
      expect(
        ((await h.okData(
              h.call('GET', '/compliance/credentials', uid: 'owner-b'),
            ))['items']!
            as List),
        isEmpty,
      );
      expect(
        (await h.call(
          'PATCH',
          '/compliance/credentials/$id',
          uid: 'owner-b',
          body: {'notes': 'x'},
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/compliance/credentials/$id/archive',
          uid: 'owner-b',
        )).statusCode,
        404,
      );
    });
  });

  group('who may use compliance', () {
    test('owners and admins can; receptionists and strangers cannot', () async {
      final h = harness();
      final tid = await h.createClinic('owner1');
      h.member('admin1', tid, 'clinic_admin');
      h.member('rec1', tid, 'receptionist');
      h.user('stranger');
      expect(
        (await h.call(
          'GET',
          '/compliance/dashboard',
          uid: 'owner1',
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'GET',
          '/compliance/dashboard',
          uid: 'admin1',
        )).statusCode,
        200,
      );
      for (final uid in ['rec1', 'stranger']) {
        expect(
          (await h.call('GET', '/compliance/dashboard', uid: uid)).statusCode,
          anyOf(403, 404),
          reason: uid,
        );
        expect(
          (await h.call(
            'POST',
            '/compliance/credentials',
            uid: uid,
            body: {},
          )).statusCode,
          anyOf(403, 404, 422),
          reason: uid,
        );
      }
      expect((await h.call('GET', '/compliance/dashboard')).statusCode, 401);
      expect(
        (await h.call(
          'GET',
          '/compliance/evidence/ce_x/file',
          uid: 'rec1',
        )).statusCode,
        403,
      );
    });

    test('every change is recorded in the clinic history', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      final e = await upload(h, 'owner1');
      await h.okData(
        review(h, tid, e['evidenceId']! as String, {'decision': 'accept'}),
      );
      final types =
          ((await h.okData(
                    h.call('GET', '/compliance/history', uid: 'owner1'),
                  ))['items']!
                  as List)
              .map((x) => (x as Map)['type'])
              .toSet();
      expect(
        types,
        containsAll([
          'applicability_set',
          'evidence_submitted',
          'evidence_accepted',
        ]),
      );
    });
  });

  group('expiry alerts', () {
    test(
      'alerts go to owners and admins at each threshold, once, with no document details',
      () async {
        final h = harness();
        final tid = await h.createClinic('owner1');
        h.member('admin1', tid, 'clinic_admin');
        h.member('rec1', tid, 'receptionist');
        final sent = <Map<String, String>>[];
        h.clinic.compliance.notifier =
            ({
              required tenantId,
              required staffUid,
              required dedupeKey,
              required title,
              required body,
            }) async {
              sent.add({
                'to': staffUid,
                'key': dedupeKey,
                'title': title,
                'body': body,
              });
            };
        await h.okData(
          h.call(
            'POST',
            '/compliance/credentials',
            uid: 'owner1',
            body: {
              'subjectType': 'practitioner',
              'subjectName': 'Dr Secret Name',
              'kind': 'practitioner_license',
              'authorityCode': 'DHA',
              'authorityName': 'DHA',
              'number': 'LIC-9999',
              'validTo': '2026-07-10',
            },
          ),
          status: 201,
        );

        expect(
          await h.clinic.compliance.scanExpiries(tid),
          0 + 2,
        ); // 39 days left: 60-day alert, 2 recipients
        expect(sent.map((s) => s['to']).toSet(), {'owner1', 'admin1'});
        expect(sent.map((s) => s['to']), isNot(contains('rec1')));
        final keys = sent.map((s) => s['key']!).toSet();
        expect(keys, hasLength(2));
        for (final s in sent) {
          expect(s['title'], 'A compliance document expires soon');
          expect(s['body'], isNot(contains('LIC-9999')));
          expect(s['body'], isNot(contains('Secret')));
        }

        // same day again: identical dedupe keys (the notification hub drops duplicates)
        sent.clear();
        await h.clinic.compliance.scanExpiries(tid);
        expect(sent.map((s) => s['key']).toSet(), keys);

        // closer to expiry: the 30-day and 7-day alerts have different keys
        sent.clear();
        h.clock.now = DateTime.utc(2026, 6, 15); // 25 days
        await h.clinic.compliance.scanExpiries(tid);
        expect(sent.map((s) => s['key']).toSet().intersection(keys), isEmpty);
        sent.clear();
        h.clock.now = DateTime.utc(2026, 7, 5); // 5 days
        await h.clinic.compliance.scanExpiries(tid);
        expect(sent.first['body'], contains('within 7 days'));

        // expired
        sent.clear();
        h.clock.now = DateTime.utc(2026, 7, 11);
        await h.clinic.compliance.scanExpiries(tid);
        expect(sent.first['title'], 'A compliance document has expired');
        expect(sent.first['body'], contains('has expired'));
      },
    );

    test('the scan persists expired approvals and records it once', () async {
      final h = harness();
      await seed(h);
      final tid = await h.createClinic('owner1');
      await confirm(h, tid, inEstablishment);
      final e = await upload(h, 'owner1', validTo: '2026-09-30');
      await h.okData(
        review(h, tid, e['evidenceId']! as String, {'decision': 'accept'}),
      );
      h.clock.now = DateTime.utc(2026, 10, 2);
      final sent = <String>[];
      h.clinic.compliance.notifier =
          ({
            required tenantId,
            required staffUid,
            required dedupeKey,
            required title,
            required body,
          }) async => sent.add(dedupeKey);
      await h.clinic.compliance.scanExpiries(tid);
      expect(
        h
            .store
            .docs['tenants/$tid/compliance_items/${inEstablishment}__$facilityReq']!['status'],
        'expired',
      );
      expect(sent, isNotEmpty);
      await h.clinic.compliance.scanExpiries(tid);
      final events = h.store.docs.entries.where(
        (e) =>
            e.key.contains('/compliance_history/') &&
            e.value['type'] == 'requirement_expired',
      );
      expect(
        events,
        hasLength(1),
        reason: 'persisted once; the second pass finds it already expired',
      );
    });

    test('with no notifier configured the scan still completes', () async {
      final h = harness();
      final tid = await h.createClinic('owner1');
      expect(await h.clinic.compliance.scanExpiries(tid), 0);
    });

    test(
      'the notification worker runs the compliance scan for every active clinic',
      () async {
        final h = harness();
        final tid = await h.createClinic('owner1');
        final scanned = <String>[];
        h.clinic.hub.tenantScans.add((t) async => scanned.add(t));
        await h.clinic.hub.tick();
        expect(scanned, contains(tid));
      },
    );
  });
}
