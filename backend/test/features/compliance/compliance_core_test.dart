import 'package:backend/features/compliance/compliance_baseline.dart';
import 'package:backend/features/compliance/compliance_core.dart';
import 'package:test/test.dart';

Map<String, Object?> req({
  String title = 'Facility licence',
  bool expiry = true,
}) => {
  'key': 'facility-license',
  'title': title,
  'description': 'd',
  'category': 'statutory',
  'appliesTo': 'facility',
  'evidence': {
    'required': true,
    'kinds': ['license'],
    'expiryTracked': expiry,
  },
  'goLiveBlocking': true,
};

void main() {
  final now = DateTime.utc(2026, 6, 1);

  group('status logic', () {
    test('a requirement with no record is not assessed', () {
      expect(
        effectiveStatus(item: null, requirement: req(), now: now),
        ComplianceStatus.notAssessed,
      );
    });

    test('an approval expires without any write, on the expiry date', () {
      final item = {
        'status': 'approved',
        'requirementHash': requirementHash(req()),
        'expiresAt': DateTime.utc(2026, 6, 10),
      };
      expect(
        effectiveStatus(item: item, requirement: req(), now: now),
        ComplianceStatus.approved,
      );
      expect(
        effectiveStatus(
          item: item,
          requirement: req(),
          now: DateTime.utc(2026, 6, 10),
        ),
        ComplianceStatus.expired,
        reason: 'valid until the instant of expiry',
      );
      expect(
        effectiveStatus(
          item: item,
          requirement: req(),
          now: DateTime.utc(2027),
        ),
        ComplianceStatus.expired,
      );
    });

    test(
      'an approval of a requirement that later changed no longer counts',
      () {
        final item = {
          'status': 'approved',
          'requirementHash': requirementHash(req()),
          'expiresAt': null,
        };
        expect(
          effectiveStatus(
            item: item,
            requirement: req(title: 'Facility licence (renewed rules)'),
            now: now,
          ),
          ComplianceStatus.pendingEvidence,
        );
      },
    );

    test('other stored statuses pass through unchanged', () {
      for (final s in ComplianceStatus.values.where(
        (s) => s != ComplianceStatus.approved,
      )) {
        expect(
          effectiveStatus(
            item: {'status': s.wireName},
            requirement: req(),
            now: now,
          ),
          s,
        );
      }
    });

    test('requirement hash ignores presentation fields but sees meaning', () {
      expect(
        requirementHash(req()),
        requirementHash({...req(), 'notes': 'x', 'owner': 'y'}),
      );
      expect(
        requirementHash(req()),
        isNot(requirementHash(req(expiry: false))),
      );
    });

    test(
      'transition table: approval needs review; nothing jumps to approved',
      () {
        expect(
          canTransition(
            ComplianceStatus.notAssessed,
            ComplianceStatus.approved,
          ),
          isFalse,
        );
        expect(
          canTransition(
            ComplianceStatus.pendingEvidence,
            ComplianceStatus.approved,
          ),
          isFalse,
        );
        expect(
          canTransition(ComplianceStatus.rejected, ComplianceStatus.approved),
          isFalse,
        );
        expect(
          canTransition(ComplianceStatus.expired, ComplianceStatus.approved),
          isFalse,
        );
        expect(
          canTransition(
            ComplianceStatus.underReview,
            ComplianceStatus.approved,
          ),
          isTrue,
        );
        expect(
          canTransition(
            ComplianceStatus.approved,
            ComplianceStatus.underReview,
          ),
          isTrue,
        );
        expect(
          canTransition(
            ComplianceStatus.notApplicable,
            ComplianceStatus.pendingEvidence,
          ),
          isTrue,
        );
        expect(
          canTransition(ComplianceStatus.approved, ComplianceStatus.approved),
          isTrue,
        );
      },
    );

    test('there is no "compliant" status anywhere', () {
      for (final s in ComplianceStatus.values) {
        expect(s.wireName, isNot(contains('complian')));
      }
      for (final a in Applicability.values) {
        expect(a.wireName, isNot(contains('complian')));
      }
    });
  });

  group('credential validity and alerts', () {
    test('valid, expiring, expired and no-expiry', () {
      expect(credentialValidity(null, now), CredentialValidity.noExpiry);
      expect(
        credentialValidity(DateTime.utc(2027), now),
        CredentialValidity.valid,
      );
      expect(
        credentialValidity(DateTime.utc(2026, 7, 15), now),
        CredentialValidity.expiring,
      );
      expect(
        credentialValidity(DateTime.utc(2026, 7, 31), now),
        CredentialValidity.expiring,
      );
      expect(
        credentialValidity(DateTime.utc(2026, 8, 2), now),
        CredentialValidity.valid,
      );
      expect(
        credentialValidity(DateTime.utc(2026, 5, 31), now),
        CredentialValidity.expired,
      );
      expect(credentialValidity(now, now), CredentialValidity.expired);
    });

    test('alert thresholds 60, 30, 7 and expired', () {
      DateTime inDays(int d) => now.add(Duration(days: d, hours: 1));
      expect(reachedAlertThreshold(inDays(90), now), isNull);
      expect(reachedAlertThreshold(inDays(61), now), isNull);
      expect(reachedAlertThreshold(inDays(60), now), 60);
      expect(reachedAlertThreshold(inDays(45), now), 60);
      expect(reachedAlertThreshold(inDays(30), now), 30);
      expect(reachedAlertThreshold(inDays(7), now), 7);
      expect(reachedAlertThreshold(inDays(1), now), 7);
      expect(
        reachedAlertThreshold(now.subtract(const Duration(days: 2)), now),
        0,
      );
    });
  });

  group('evidence files', () {
    test('type comes from the file bytes, never the declared type', () {
      expect(
        detectEvidenceMime([0x25, 0x50, 0x44, 0x46, 0x2D]),
        'application/pdf',
      );
      expect(
        detectEvidenceMime([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]),
        'image/png',
      );
      expect(detectEvidenceMime([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(detectEvidenceMime('<html>'.codeUnits), isNull);
      expect(detectEvidenceMime('MZ'.codeUnits), isNull);
      expect(detectEvidenceMime([]), isNull);
      expect(extensionForMime('application/pdf'), 'pdf');
    });
  });

  group('baseline registers', () {
    final profiles = baselineProfiles();

    test(
      'India and the UAE are covered; the UAE is not hard-coded to one authority',
      () {
        final keys = profiles.map((p) => p['key']).toSet();
        expect(
          keys,
          containsAll([
            'in-data-protection',
            'in-practitioner-registration',
            'in-clinical-establishment',
            'in-abdm-readiness',
          ]),
        );
        expect(
          keys,
          containsAll([
            'ae-dha-dubai',
            'ae-doh-abu-dhabi',
            'ae-mohap-northern-emirates',
            'ae-health-data-privacy',
          ]),
        );
        final ae = profiles
            .where(
              (p) =>
                  p['countryCode'] == 'AE' &&
                  (p['domain'] == 'facility_licensing'),
            )
            .toList();
        expect(ae.map((p) => (p['authority']! as Map)['code']).toSet(), {
          'DHA',
          'DOH',
          'MOHAP',
        });
        for (final p in ae) {
          expect('${p['appliesWhenNote']}', contains('per clinic'));
        }
      },
    );

    test('everything ships as an unvalidated draft with provenance', () {
      for (final p in profiles) {
        final lr = p['legalReview']! as Map<String, Object?>;
        expect(lr['status'], 'pending', reason: '${p['key']}');
        expect(lr['reviewedBy'], isNull);
        for (final r
            in (p['requirements']! as List).cast<Map<String, Object?>>()) {
          expect(r['confidence'], 'low', reason: '${p['key']}/${r['key']}');
          expect(r['reviewedOn'], isNull);
          expect('${r['owner']}', isNotEmpty);
          expect('${(r['source']! as Map)['reference']}', isNotEmpty);
          expect('${r['notes']}', contains('Unvalidated'));
        }
      }
    });

    test('ABDM is a readiness checklist only, never a claimed integration', () {
      final abdm = profiles.firstWhere((p) => p['key'] == 'in-abdm-readiness');
      expect('${abdm['appliesWhenNote']}', contains('NO live ABDM'));
      for (final r
          in (abdm['requirements']! as List).cast<Map<String, Object?>>()) {
        expect(r['category'], 'optional_integration');
      }
    });

    test('no text claims compliance, certification or approval', () {
      final text = profiles.toString().toLowerCase();
      for (final bad in [
        'is compliant',
        'are compliant',
        'fully compliant',
        'certified by',
        'approved by the regulator',
        'guarantee',
      ]) {
        expect(text.contains(bad), isFalse, reason: bad);
      }
    });

    test('requirement keys are unique inside each profile', () {
      for (final p in profiles) {
        final keys = (p['requirements']! as List)
            .map((r) => (r as Map)['key'])
            .toList();
        expect(keys.toSet().length, keys.length, reason: '${p['key']}');
      }
    });
  });
}
