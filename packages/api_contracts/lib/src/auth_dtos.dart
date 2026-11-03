import 'package:common_models/common_models.dart';

/// Response of `GET /auth/me`: the caller's verified profile.
class AuthProfileDto {
  const AuthProfileDto({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.emailVerified,
    required this.accountStatus,
    this.phoneNumber,
    this.profileImageUrl,
    this.lastLoginAt,
  });

  factory AuthProfileDto.fromJson(Map<String, Object?> json) => AuthProfileDto(
    uid: json['uid']! as String,
    displayName: json['displayName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    emailVerified: json['emailVerified'] as bool? ?? false,
    accountStatus:
        AccountStatus.tryParse(json['accountStatus'] as String?) ??
        AccountStatus.disabled,
    phoneNumber: json['phoneNumber'] as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    lastLoginAt: json['lastLoginAt'] as String?,
  );

  final String uid;
  final String displayName;
  final String email;
  final bool emailVerified;
  final AccountStatus accountStatus;
  final String? phoneNumber;
  final String? profileImageUrl;
  final String? lastLoginAt;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'email': email,
    'emailVerified': emailVerified,
    'accountStatus': accountStatus.wireName,
    if (phoneNumber != null) 'phoneNumber': phoneNumber,
    if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
    if (lastLoginAt != null) 'lastLoginAt': lastLoginAt,
  };
}

/// Response of `GET /auth/session` and `POST /auth/profile/initialize`.
///
/// [platformRole] and [memberships] are *informational*: they let the UI pick
/// a screen. The backend re-authorizes every request on its own.
class AuthSessionDto {
  const AuthSessionDto({
    required this.uid,
    required this.accountStatus,
    required this.emailVerified,
    required this.accessGranted,
    this.platformRole,
    this.memberships = const [],
  });

  factory AuthSessionDto.fromJson(Map<String, Object?> json) => AuthSessionDto(
    uid: json['uid']! as String,
    accountStatus:
        AccountStatus.tryParse(json['accountStatus'] as String?) ??
        AccountStatus.disabled,
    emailVerified: json['emailVerified'] as bool? ?? false,
    accessGranted: json['accessGranted'] as bool? ?? false,
    platformRole: PlatformRole.tryParse(json['platformRole'] as String?),
    memberships: ((json['memberships'] as List?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => MembershipSummaryDto.fromJson(m.cast<String, Object?>()))
        .toList(),
  );

  final String uid;
  final AccountStatus accountStatus;
  final bool emailVerified;

  /// True when the account itself may use protected features (status active).
  final bool accessGranted;
  final PlatformRole? platformRole;

  /// Clinic memberships resolved server-side. Always empty until Phase 3.
  final List<MembershipSummaryDto> memberships;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'accountStatus': accountStatus.wireName,
    'emailVerified': emailVerified,
    'accessGranted': accessGranted,
    if (platformRole != null) 'platformRole': platformRole!.wireName,
    'memberships': memberships.map((m) => m.toJson()).toList(),
  };
}

/// Contract for a resolved clinic membership (filled in from Phase 3).
class MembershipSummaryDto {
  const MembershipSummaryDto({
    required this.tenantId,
    required this.role,
    this.branchIds = const [],
  });

  factory MembershipSummaryDto.fromJson(Map<String, Object?> json) =>
      MembershipSummaryDto(
        tenantId: json['tenantId']! as String,
        role: json['role']! as String,
        branchIds: ((json['branchIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );

  final String tenantId;
  final String role;
  final List<String> branchIds;

  Map<String, Object?> toJson() => {
    'tenantId': tenantId,
    'role': role,
    'branchIds': branchIds,
  };
}
