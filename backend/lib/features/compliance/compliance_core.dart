import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Phase 14: compliance framework primitives.
///
/// EazyClinic does not decide whether a clinic is "compliant". It records
/// *requirements* (from a versioned register that counsel must validate),
/// *evidence* a clinic supplies, and a *platform reviewer's* decision about
/// that evidence. There is deliberately no "compliant" value anywhere.

/// Status of one requirement for one clinic.
enum ComplianceStatus {
  notAssessed('not_assessed'),
  pendingEvidence('pending_evidence'),
  underReview('under_review'),
  approved('approved'),
  rejected('rejected'),
  expired('expired'),
  notApplicable('not_applicable');

  const ComplianceStatus(this.wireName);

  final String wireName;

  static ComplianceStatus? tryParse(Object? v) {
    for (final s in values) {
      if (s.wireName == v) return s;
    }
    return null;
  }
}

/// Whether a compliance profile applies to a clinic. The safe default is
/// [unknown]: nothing is assumed to apply, and nothing is shown as met.
enum Applicability {
  unknown('unknown'),
  applies('applies'),
  notApplicable('not_applicable');

  const Applicability(this.wireName);

  final String wireName;

  static Applicability? tryParse(Object? v) {
    for (final s in values) {
      if (s.wireName == v) return s;
    }
    return null;
  }
}

const List<String> requirementCategories = [
  'statutory',
  'contractual',
  'platform_control',
  'optional_integration',
];

const List<String> requirementSubjects = [
  'facility',
  'practitioner',
  'platform',
];
const List<String> confidenceLevels = ['low', 'medium', 'high'];
const List<String> evidenceKinds = [
  'license',
  'registration',
  'certificate',
  'policy',
  'assessment',
  'agreement',
  'other',
];

/// Allowed evidence upload types (checked against the file's own bytes).
const int maxEvidenceBytes = 3 * 1024 * 1024;

/// Detects PDF/PNG/JPEG from magic bytes; null for anything else. The
/// declared content type is never trusted.
String? detectEvidenceMime(List<int> bytes) {
  bool starts(List<int> sig) =>
      bytes.length >= sig.length &&
      [for (var i = 0; i < sig.length; i++) bytes[i] == sig[i]].every((b) => b);
  if (starts([0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  if (starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  return null;
}

String extensionForMime(String mime) => switch (mime) {
  'application/pdf' => 'pdf',
  'image/png' => 'png',
  _ => 'jpg',
};

/// Stable hash of a requirement's meaning. When the requirement changes after
/// a clinic's evidence was approved, the approval no longer applies.
String requirementHash(Map<String, Object?> requirement) {
  const fields = [
    'key',
    'title',
    'description',
    'category',
    'appliesTo',
    'evidence',
    'goLiveBlocking',
  ];
  final canonical = {for (final f in fields) f: requirement[f]};
  return sha256
      .convert(utf8.encode(jsonEncode(_sorted(canonical))))
      .toString()
      .substring(0, 16);
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  return v;
}

/// The status a clinic's requirement actually has *now*.
///
/// * no record → `not_assessed`
/// * an approval whose evidence has expired → `expired`
/// * an approval of a requirement that has since changed → `pending_evidence`
///   (a changed requirement must be evidenced again)
ComplianceStatus effectiveStatus({
  required Map<String, Object?>? item,
  required Map<String, Object?> requirement,
  required DateTime now,
}) {
  if (item == null) return ComplianceStatus.notAssessed;
  final stored =
      ComplianceStatus.tryParse(item['status']) ?? ComplianceStatus.notAssessed;
  if (stored == ComplianceStatus.approved) {
    if (item['requirementHash'] != requirementHash(requirement)) {
      return ComplianceStatus.pendingEvidence;
    }
    final expires = item['expiresAt'];
    if (expires is DateTime && !expires.isAfter(now)) {
      return ComplianceStatus.expired;
    }
  }
  return stored;
}

/// Allowed manual transitions (reviewer or clinic action). System transitions
/// to `expired` are handled by [effectiveStatus] and the expiry scan.
const Map<ComplianceStatus, Set<ComplianceStatus>> allowedTransitions = {
  ComplianceStatus.notAssessed: {
    ComplianceStatus.pendingEvidence,
    ComplianceStatus.underReview,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.pendingEvidence: {
    ComplianceStatus.underReview,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.underReview: {
    ComplianceStatus.approved,
    ComplianceStatus.rejected,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.approved: {
    ComplianceStatus.underReview,
    ComplianceStatus.expired,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.rejected: {
    ComplianceStatus.underReview,
    ComplianceStatus.pendingEvidence,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.expired: {
    ComplianceStatus.underReview,
    ComplianceStatus.notApplicable,
  },
  ComplianceStatus.notApplicable: {
    ComplianceStatus.pendingEvidence,
    ComplianceStatus.underReview,
  },
};

bool canTransition(ComplianceStatus from, ComplianceStatus to) =>
    from == to || (allowedTransitions[from]?.contains(to) ?? false);

/// How a credential's validity looks today.
enum CredentialValidity { valid, expiring, expired, noExpiry }

const int expiryWarningDays = 60;

/// Thresholds (days before expiry) at which alerts are raised; 0 = expired.
const List<int> expiryAlertDays = [60, 30, 7, 0];

CredentialValidity credentialValidity(DateTime? validTo, DateTime now) {
  if (validTo == null) return CredentialValidity.noExpiry;
  if (!validTo.isAfter(now)) return CredentialValidity.expired;
  if (validTo.difference(now).inDays <= expiryWarningDays) {
    return CredentialValidity.expiring;
  }
  return CredentialValidity.valid;
}

/// Smallest alert threshold already reached (60, 30, 7 or 0), or null.
int? reachedAlertThreshold(DateTime validTo, DateTime now) {
  final days = validTo.difference(now).inDays;
  final remaining = validTo.isAfter(now) ? days : -1;
  int? hit;
  for (final t in expiryAlertDays) {
    if (remaining <= t) hit = t;
  }
  return hit;
}

String dateOnly(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);
