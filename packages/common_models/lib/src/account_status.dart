/// Lifecycle state of a platform user account (`platform_users/{uid}`).
///
/// The status is stored server-side and is the only source of truth for
/// whether an authenticated Firebase identity may use the application.
enum AccountStatus {
  /// Profile exists but the e-mail address is not verified yet.
  pending('pending'),

  /// Normal operating state.
  active('active'),

  /// Temporarily blocked by an administrator or a security policy. Reversible.
  suspended('suspended'),

  /// Permanently closed. Terminal: a disabled account is never re-opened.
  disabled('disabled');

  const AccountStatus(this.wireName);

  /// Stable value used in the API and in Firestore.
  final String wireName;

  /// Whether the account may call business (non-auth) endpoints.
  bool get canAccessProtectedFeatures => this == AccountStatus.active;

  /// Allowed transitions. `disabled` has none. Only server-side workflows may
  /// perform them; ordinary clients can never change an account status.
  static const Map<AccountStatus, Set<AccountStatus>> _transitions = {
    AccountStatus.pending: {
      AccountStatus.active,
      AccountStatus.suspended,
      AccountStatus.disabled,
    },
    AccountStatus.active: {AccountStatus.suspended, AccountStatus.disabled},
    AccountStatus.suspended: {AccountStatus.active, AccountStatus.disabled},
    AccountStatus.disabled: {},
  };

  bool canTransitionTo(AccountStatus next) =>
      _transitions[this]!.contains(next);

  static AccountStatus? tryParse(String? value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}
