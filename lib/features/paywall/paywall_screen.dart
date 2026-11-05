import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/brand_logo.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

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
    final title = account.isExpired || fromExpired
        ? s.paywallTitle
        : s.choosePlan;
    if (xplm) {
      return XplmHtmlPage(
        title: 'Подписка',
        child: _XplmPayBody(controller: controller),
      );
    }

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
                      Text(
                        s.paywallSubtitle,
                        style: const TextStyle(height: 1.6),
                      ),
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
                    style: TextStyle(color: muted, height: 1.4, fontSize: 13),
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
    const features = [
      'Безлимитный трафик',
      'Серверы в 3 странах',
      'Два устройства одновременно',
      'Блокировка рекламы',
    ];
    return Stack(
      children: [
        const Positioned.fill(child: XplmHtmlEarth(screen: 'subscription')),
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
          children: [
            SizedBox(
              height: 190,
              child: LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  maxWidth: constraints.maxWidth + 6,
                  child: Image.asset(
                    'assets/brand/xplm_gift.png',
                    width: constraints.maxWidth + 6,
                    height: 190,
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Попробуйте XPLM VPN\nбесплатно 14 дней!',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                  letterSpacing: -.25,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text(
                'Без привязки карты\nи автосписаний',
                style: TextStyle(
                  color: Color(0xFFB2C2DC),
                  fontSize: 18,
                  height: 1.23,
                ),
              ),
            ),
            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Column(
                children: [
                  for (var i = 0; i < features.length; i++) ...[
                    Row(
                      children: [
                        Container(
                          width: 19,
                          height: 19,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF008CEB),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF008AFF),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            features[i],
                            style: const TextStyle(
                              fontSize: 14,
                              height: 19 / 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (i < features.length - 1) const SizedBox(height: 11),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 25),
            XplmHtmlGlass(
              padding: const EdgeInsets.fromLTRB(9, 13, 9, 0),
              child: Column(
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Text(
                              brand.priceLabel,
                              style: const TextStyle(
                                fontSize: 39,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'за 30 дней',
                              style: TextStyle(fontSize: 14, height: 1.05),
                            ),
                          ],
                        ),
                      ),
                      const Positioned(
                        right: 35,
                        top: 9,
                        child: Icon(
                          Icons.calendar_month_outlined,
                          size: 31,
                          color: Color(0xFF078BDB),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  XplmHtmlButton(
                    label: 'Оформить подписку ›',
                    onPressed: () => launchUrl(
                      Uri.parse(brand.payUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: Color(0xFF139CE3),
                ),
                SizedBox(width: 9),
                Text(
                  'Безопасная оплата\nчерез СБП',
                  style: TextStyle(
                    color: Color(0xFF9BB4CE),
                    fontSize: 11,
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
                        if (context.mounted && Navigator.of(context).canPop()) {
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
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

Future<void> openPaywall(BuildContext context, {bool fromExpired = false}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(fromExpired: fromExpired),
      fullscreenDialog: true,
    ),
  );
}
