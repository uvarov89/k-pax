import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/brand_logo.dart';
import 'package:pulse_vpn/app/theme/app_layout.dart';
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
        showBack: true,
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppLayout.pagePad,
                vertical: AppLayout.block,
              ),
              children: [
                const BrandLogo(size: 96),
                const SizedBox(height: AppLayout.block),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppLayout.stack),
                Text(
                  s.paywallSubtitle,
                  style: TextStyle(color: secondary, height: 1.6),
                ),
                if (account.hasAccess) ...[
                  const SizedBox(height: AppLayout.stack),
                  Text(
                    '${s.planName} · ${s.daysLeft(account.daysRemaining)}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppLayout.section),
                Container(
                  padding: const EdgeInsets.all(AppLayout.cardPad),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppLayout.radiusCard),
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
                      const SizedBox(height: AppLayout.stack),
                      Text(
                        s.paywallSubtitle,
                        style: const TextStyle(height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppLayout.block),
                Text(
                  s.paymentNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.45, fontSize: 14),
                ),
                const SizedBox(height: AppLayout.block),
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
                  const SizedBox(height: AppLayout.stack),
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
                  const SizedBox(height: AppLayout.tight),
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
          padding: const EdgeInsets.fromLTRB(
            AppLayout.pagePad,
            10,
            AppLayout.pagePad,
            AppLayout.section,
          ),
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
            const SizedBox(height: AppLayout.stack),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppLayout.tight),
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
            const SizedBox(height: AppLayout.stack),
            const Padding(
              padding: EdgeInsets.only(left: AppLayout.tight),
              child: Text(
                'Без привязки карты\nи автосписаний',
                style: TextStyle(
                  color: XplmColors.ink2,
                  fontSize: 18,
                  height: 1.23,
                ),
              ),
            ),
            const SizedBox(height: AppLayout.section),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppLayout.tight),
              child: Column(
                children: [
                  for (var i = 0; i < features.length; i++) ...[
                    Row(
                      children: [
                        Container(
                          width: AppLayout.iconSm,
                          height: AppLayout.iconSm,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: XplmColors.cyan,
                            boxShadow: [
                              BoxShadow(
                                color: XplmColors.cyan,
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
                        const SizedBox(width: AppLayout.block),
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
                    if (i < features.length - 1)
                      const SizedBox(height: AppLayout.stack),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppLayout.section),
            XplmHtmlGlass(
              padding: const EdgeInsets.fromLTRB(
                AppLayout.stack,
                AppLayout.stack,
                AppLayout.stack,
                0,
              ),
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
                          color: XplmColors.neonDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.tight),
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
            const SizedBox(height: AppLayout.block),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: AppLayout.iconSm,
                  color: XplmColors.cyan,
                ),
                SizedBox(width: AppLayout.tight),
                Text(
                  'Безопасная оплата\nчерез СБП',
                  style: TextStyle(
                    color: XplmColors.ink3,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
            if (controller.subscriptionUrl != null) ...[
              const SizedBox(height: AppLayout.block),
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
              const SizedBox(height: AppLayout.tight),
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
  if (AppBrand.current.isXplm && XplmTabNavigation.go(context, 2)) {
    return Future<void>.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(fromExpired: fromExpired),
      fullscreenDialog: true,
    ),
  );
}
