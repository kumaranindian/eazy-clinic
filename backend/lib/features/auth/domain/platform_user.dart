import 'package:common_models/common_models.dart';

/// Server-side identity record: `platform_users/{uid}`.
///
/// Only the backend writes this document. [platformRole] is assigned by
/// authorized platform workflows (never by registration) and is `null` for
/// ordinary users.
class PlatformUser {
  const PlatformUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.emailVerified,
    required this.accountStatus,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.phoneNumber,
    this.profileImageUrl,
    this.platformRole,
    this.preferredLanguage,
  });

  final String uid;
  final String displayName;
  final String email;
  final bool emailVerified;
  final AccountStatus accountStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  final String? phoneNumber;
  final String? profileImageUrl;
  final PlatformRole? platformRole;

  /// UI language chosen by the user (`en`, `ar`, `hi`, `ta`), presentation only.
  final String? preferredLanguage;

  PlatformUser copyWith({
    String? displayName,
    String? email,
    bool? emailVerified,
    AccountStatus? accountStatus,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) => PlatformUser(
    uid: uid,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    accountStatus: accountStatus ?? this.accountStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    phoneNumber: phoneNumber,
    profileImageUrl: profileImageUrl,
    platformRole: platformRole,
    preferredLanguage: preferredLanguage,
  );

  /// Storage representation (scalars and [DateTime] only).
  Map<String, Object?> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'email': email,
    'emailVerified': emailVerified,
    'accountStatus': accountStatus.wireName,
    'createdAt': createdAt.toUtc(),
    'updatedAt': updatedAt.toUtc(),
    'lastLoginAt': lastLoginAt?.toUtc(),
    'phoneNumber': phoneNumber,
    'profileImageUrl': profileImageUrl,
    'platformRole': platformRole?.wireName,
    'preferredLanguage': preferredLanguage,
  };

  /// Returns `null` when the stored document is malformed. An unknown status
  /// is treated as `disabled` (deny by default).
  static PlatformUser? fromMap(Map<String, Object?> map) {
    final uid = map['uid'];
    final created = map['createdAt'];
    final updated = map['updatedAt'];
    if (uid is! String || created is! DateTime || updated is! DateTime) {
      return null;
    }
    return PlatformUser(
      uid: uid,
      displayName: map['displayName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      emailVerified: map['emailVerified'] as bool? ?? false,
      accountStatus:
          AccountStatus.tryParse(map['accountStatus'] as String?) ??
          AccountStatus.disabled,
      createdAt: created,
      updatedAt: updated,
      lastLoginAt: map['lastLoginAt'] as DateTime?,
      phoneNumber: map['phoneNumber'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      platformRole: PlatformRole.tryParse(map['platformRole'] as String?),
      preferredLanguage:
          isSupportedUiLanguage(map['preferredLanguage'] as String?)
          ? map['preferredLanguage'] as String?
          : null,
    );
  }
}
