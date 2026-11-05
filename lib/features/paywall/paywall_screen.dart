import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/brand_logo.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({
    super.key,
    this.fromExpired = false,
    this.embeddedInShell = false,
  });

  final bool fromExpired;
  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final xplm = AppBrand.current.isXplm;
    final muted = xplm
        ? XplmColors.ink3
        : (isDark ? NordColors.textMuted : NordColors.lightTextMuted);
    final secondary = xplm
        ? XplmColors.ink2
        : (isDark ? NordColors.textSecondary : NordColors.lightTextSecondary);
    final surface = xplm
        ? XplmColors.surface
        : (isDark ? NordColors.surface : NordColors.lightSurface);
    final accent = xplm ? XplmColors.cyan : NordColors.accent;
    final title = account.isExpired || fromExpired ? s.paywallTitle : s.choosePlan;

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(xplm ? 'Подписка' : s.subscription),
        automaticallyImplyLeading: !embeddedInShell,
        leading: embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
      ),
      body: xplm
          ? _XplmPayBody(controller: controller)
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              children: [
                const BrandLogo(size: 96),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  s.paywallSubtitle,
                  style: TextStyle(color: secondary, height: 1.6),
                ),
                if (account.hasAccess) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${s.planName} · ${s.daysLeft(account.daysRemaining)}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.planName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(s.paywallSubtitle, style: const TextStyle(height: 1.6)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.paymentNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.45, fontSize: 14),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => launchUrl(
                      Uri.parse(AppBrand.current.payUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(s.buyOnSite),
                  ),
                ),
                if (controller.subscriptionUrl != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: controller.isRefreshingServers
                          ? null
                          : () async {
                              await controller.refreshAccessAfterPayment(
                                openAccount: true,
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                            },
                      child: Text(s.refreshAccess),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.refreshAccessHint,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: muted, height: 1.4, fontSize: 13),
                  ),
                ],
              ],
            ),
    );
    if (embeddedInShell) return scaffold;
    return NordBackground(child: scaffold);
  }
}

class _XplmPayBody extends StatelessWidget {
  const _XplmPayBody({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.strings;
    final brand = AppBrand.current;
    final features = <String>[
      'Безлимитный трафик',
      'Серверы в 3 странах',
      'Два устройства одновременно',
      'Блокировка рекламы',
    ];

    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          bottom: -60,
          height: 240,
          child: Opacity(
            opacity: 0.5,
            child: XplmEarthBackdrop(
              width: 420,
              height: 250,
              rotate: -8,
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            const _GiftScene(),
            const SizedBox(height: 6),
            const Text(
              'Попробуйте XPLM VPN\nбесплатно 14 дней!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.12,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Без привязки карты\nи автосписаний',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFB2C2DC),
                fontSize: 14,
                height: 1.23,
              ),
            ),
            const SizedBox(height: 16),
            for (final line in features) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 9, 6),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF008CEB),
                        boxShadow: [
                          BoxShadow(color: Color(0xFF008AFF), blurRadius: 6),
                        ],
                      ),
                      child: const Text(
                        '✓',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            XplmGlass(
              padding: const EdgeInsets.fromLTRB(7, 8, 7, 0),
              child: Column(
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Text(
                              brand.priceLabel.contains('₽')
                                  ? brand.priceLabel
                                  : '299 ₽',
                              style: const TextStyle(
                                fontSize: 31,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                            const Text(
                              'за 30 дней',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: XplmColors.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Positioned(
                        right: 18,
                        top: 8,
                        child: Icon(
                          Icons.calendar_month_outlined,
                          color: Color(0xFF078BDB),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  XplmPrimaryButton(
                    label: 'Оформить подписку ›',
                    height: 40,
                    onPressed: () => launchUrl(
                      Uri.parse(brand.payUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 20, color: Color(0xFF139CE3)),
                SizedBox(width: 9),
                Text(
                  'Безопасная оплата\nчерез СБП',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: Color(0xFF9BB4CE),
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
              ],
            ),
            if (controller.subscriptionUrl != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: controller.isRefreshingServers
                    ? null
                    : () async {
                        await controller.refreshAccessAfterPayment(
                          openAccount: true,
                        );
                        if (!context.mounted) return;
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                child: Text(s.refreshAccess),
              ),
              const SizedBox(height: 6),
              Text(
                s.refreshAccessHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: XplmColors.ink3,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Exact Codex gift scene (box + lid + ribbon + bows + trial badge).
class _GiftScene extends StatelessWidget {
  const _GiftScene();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: const Border(top: BorderSide(color: Color(0xFF154F95))),
                gradient: RadialGradient(
                  center: const Alignment(0, 0.4),
                  radius: 0.9,
                  colors: [
                    const Color(0xFF0063F4).withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 2,
            child: Transform.rotate(
              angle: 8 * 3.14159 / 180,
              child: Container(
                width: 173,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(90),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF1788FF), width: 2),
                    right: BorderSide(color: Color(0xFF1788FF), width: 2),
                    bottom: BorderSide(color: Color(0xFF1788FF), width: 2),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFF008AFF), blurRadius: 7, offset: Offset(0, 4)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 42,
            top: 28,
            child: Transform.rotate(
              angle: -9 * 3.14159 / 180,
              child: SizedBox(
                width: 93,
                height: 90,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 7,
                      top: 24,
                      child: Container(
                        width: 79,
                        height: 59,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF137BFF)),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0076FA),
                              Color(0xFF0032A8),
                              Color(0xFF0082FF),
                              Color(0xFF0047B3),
                            ],
                            stops: [0.0, 0.48, 0.49, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF000661).withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(-8, -3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 2,
                      top: 19,
                      child: Transform(
                        transform: Matrix4.skewY(-0.05),
                        child: Container(
                          width: 89,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: const Color(0xFF21A1FF)),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2CB9FF), Color(0xFF004AD8)],
                              stops: [0.0, 0.7],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 36,
                      top: 20,
                      child: Container(
                        width: 17,
                        height: 64,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF2EC7FF),
                              Color(0xFF007BDD),
                              Color(0xFF4BDCFF),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF001C91),
                              blurRadius: 5,
                              offset: Offset(2, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 15,
                      top: 3,
                      child: Transform.rotate(
                        angle: 27 * 3.14159 / 180,
                        child: _Bow(),
                      ),
                    ),
                    Positioned(
                      left: 45,
                      top: 0,
                      child: Transform.rotate(
                        angle: 105 * 3.14159 / 180,
                        child: _Bow(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 21,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                border: Border.fromBorderSide(BorderSide(color: Color(0xFF1E9FFF))),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0BC6FF), Color(0xFF0054C1)],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFF008CFF), blurRadius: 14),
                ],
              ),
              child: const Text.rich(
                TextSpan(
                  text: '14 дней',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Colors.white,
                    height: 1.1,
                  ),
                  children: [
                    TextSpan(
                      text: '\nбесплатно',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const Positioned(
            left: 18,
            top: 4,
            child: Text('✦', style: TextStyle(color: Color(0xFF32BFFF), fontSize: 14)),
          ),
          const Positioned(
            right: 32,
            top: 5,
            child: Text('✧', style: TextStyle(color: Color(0xFF32BFFF), fontSize: 14)),
          ),
          const Positioned(
            right: 10,
            bottom: 20,
            child: Text('✦', style: TextStyle(color: Color(0xFF32BFFF), fontSize: 14)),
          ),
          Positioned(
            left: 24,
            bottom: 12,
            child: Container(
              width: 150,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                color: const Color(0xFF00AAFF),
                boxShadow: const [
                  BoxShadow(color: Color(0xFF00AAFF), blurRadius: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 23,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(90),
          topRight: Radius.circular(90),
          bottomRight: Radius.circular(90),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF88EFFF), Color(0xFF009DFF), Color(0xFF0042BC)],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9DEAFF).withValues(alpha: 0.7),
            blurRadius: 4,
            offset: const Offset(2, 3),
          ),
        ],
      ),
    );
  }
}

Future<void> openPaywall(
  BuildContext context, {
  bool fromExpired = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(fromExpired: fromExpired),
      fullscreenDialog: true,
    ),
  );
}
