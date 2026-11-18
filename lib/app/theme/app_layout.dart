/// Shared 4pt layout rhythm for K-Pax and X-Plm.
///
/// Use these instead of ad-hoc 17/21/23/9/3 paddings on main chrome screens.
abstract final class AppLayout {
  // Spacing scale (4pt grid)
  static const double hair = 4;
  static const double tight = 8;
  static const double stack = 12;
  static const double block = 16;
  static const double section = 24;

  /// Horizontal page inset (both brands).
  static const double pagePad = 24;

  /// Standard card / glass inner padding.
  static const double cardPad = 16;

  /// Content column max width (phone + Windows centered shell).
  static const double maxContent = 440;

  // Icon sizes
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 28;

  /// Shared card corner radius for glass/list cards.
  static const double radiusCard = 16;

  /// Primary CTA / pill radius (X-Plm HTML primary buttons stay rounder).
  static const double radiusPill = 25;
}
