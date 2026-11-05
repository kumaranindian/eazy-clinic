import 'package:design_system/design_system.dart';

/// Plain-language labels for compliance statuses. The wording never says a
/// clinic "is compliant": it describes where the evidence stands.
String complianceStatusLabel(Object? s) => switch ('$s') {
  'not_assessed' => 'Not assessed',
  'pending_evidence' => 'Evidence needed',
  'under_review' => 'Under review',
  'approved' => 'Evidence approved',
  'rejected' => 'Rejected',
  'expired' => 'Expired',
  'not_applicable' => 'Not applicable',
  _ => '$s',
};

EcStatusTone complianceStatusTone(Object? s) => switch ('$s') {
  'approved' => EcStatusTone.success,
  'under_review' => EcStatusTone.info,
  'pending_evidence' => EcStatusTone.warning,
  'rejected' || 'expired' => EcStatusTone.error,
  _ => EcStatusTone.neutral,
};

String readinessLabel(Object? r) => switch ('$r') {
  'applicability_unconfirmed' =>
    'Waiting for a reviewer to confirm which registers apply to your clinic.',
  'awaiting_legal_validation' =>
    'The registers that apply have not been validated by counsel yet.',
  'incomplete' => 'Some requirements still need evidence or review.',
  'all_required_evidence_approved' =>
    'All required evidence has been approved by a reviewer. This is not a certification and not legal advice.',
  'country_not_assigned' =>
    'Your clinic has no legal country yet. Contact support.',
  _ => '$r',
};

EcStatusTone readinessTone(Object? r) => switch ('$r') {
  'all_required_evidence_approved' => EcStatusTone.success,
  'incomplete' => EcStatusTone.warning,
  _ => EcStatusTone.info,
};

String validityLabel(Object? v) => switch ('$v') {
  'valid' => 'Valid',
  'expiring' => 'Expiring soon',
  'expired' => 'Expired',
  'noExpiry' => 'No end date recorded',
  _ => '$v',
};

EcStatusTone validityTone(Object? v) => switch ('$v') {
  'valid' => EcStatusTone.success,
  'expiring' => EcStatusTone.warning,
  'expired' => EcStatusTone.error,
  _ => EcStatusTone.neutral,
};

String humanizeKey(Object? v) {
  final s = '${v ?? ''}'.replaceAll(RegExp(r'[_.-]'), ' ').trim();
  return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
}

String verificationLabel(Object? v) => switch ('$v') {
  'verified' => 'Verified by reviewer',
  'rejected' => 'Rejected by reviewer',
  _ => 'Not verified',
};

EcStatusTone verificationTone(Object? v) => switch ('$v') {
  'verified' => EcStatusTone.success,
  'rejected' => EcStatusTone.error,
  _ => EcStatusTone.neutral,
};
