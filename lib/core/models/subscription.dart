enum SubscriptionPlan { trial, basic, pro, expired }

extension SubscriptionPlanX on SubscriptionPlan {
  bool get hasAccess => this != SubscriptionPlan.expired;

  bool get isPremiumPaid => this != SubscriptionPlan.expired;

  int get priceRub => 0;
}

class UserAccount {
  const UserAccount({
    required this.userId,
    required this.referralCode,
    required this.plan,
    required this.trialStartedAt,
    required this.accessExpiresAt,
    this.referralMonthsEarned = 0,
    this.friendsConverted = 0,
    this.displayName,
  });

  final String userId;
  final String referralCode;
  final SubscriptionPlan plan;
  final DateTime trialStartedAt;
  final DateTime accessExpiresAt;
  final int referralMonthsEarned;
  final int friendsConverted;
  final String? displayName;

  static const referralYearlyCap = 12;

  int get trialDaysTotal => 14;

  int get daysRemaining {
    final diff = accessExpiresAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get isExpired =>
      plan == SubscriptionPlan.expired ||
      DateTime.now().isAfter(accessExpiresAt);

  bool get hasAccess => !isExpired && plan.hasAccess;

  String get referralLink => 'https://pulse.app/r/$referralCode';

  UserAccount copyWith({
    String? userId,
    String? referralCode,
    SubscriptionPlan? plan,
    DateTime? trialStartedAt,
    DateTime? accessExpiresAt,
    int? referralMonthsEarned,
    int? friendsConverted,
    String? displayName,
  }) {
    return UserAccount(
      userId: userId ?? this.userId,
      referralCode: referralCode ?? this.referralCode,
      plan: plan ?? this.plan,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
      referralMonthsEarned: referralMonthsEarned ?? this.referralMonthsEarned,
      friendsConverted: friendsConverted ?? this.friendsConverted,
      displayName: displayName ?? this.displayName,
    );
  }

  static UserAccount empty() {
    final now = DateTime.now();
    return UserAccount(
      userId: '',
      referralCode: '',
      plan: SubscriptionPlan.expired,
      trialStartedAt: now,
      accessExpiresAt: now,
    );
  }

  static UserAccount freshTrial() {
    final now = DateTime.now();
    final id = _randomCode(8);
    return UserAccount(
      userId: 'u_$id',
      referralCode: _randomCode(6).toUpperCase(),
      plan: SubscriptionPlan.trial,
      trialStartedAt: now,
      accessExpiresAt: now.add(const Duration(days: 14)),
      displayName: 'Guest',
    );
  }

  static String _randomCode(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final seed = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    var x = seed;
    for (var i = 0; i < length; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      buffer.write(chars[x % chars.length]);
    }
    return buffer.toString();
  }
}
