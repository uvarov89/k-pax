import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/brand_logo.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/settings/app_update_prompt.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
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
    final border = xplm
        ? XplmColors.line
        : (isDark ? NordColors.border : NordColors.lightBorder);
    final theses = [
      (s.aboutThesisQuietTitle, s.aboutThesisQuietBody),
      (s.aboutThesisLinkTitle, s.aboutThesisLinkBody),
      (s.aboutThesisPayTitle, s.aboutThesisPayBody),
    ];

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.about),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Center(child: BrandLogo(size: 88)),
          const SizedBox(height: 16),
          Text(
            s.aboutLead,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, height: 1.55, fontSize: 15),
          ),
          const SizedBox(height: 22),
          for (final thesis in theses) ...[
            _AboutPanel(
              surface: surface,
              border: border,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thesis.$1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    thesis.$2,
                    style: TextStyle(color: secondary, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Text(
            s.aboutChangelogTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: secondary,
            ),
          ),
          const SizedBox(height: 10),
          _AboutPanel(
            surface: surface,
            border: border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < s.aboutChangelog.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 6,
                          height: 6,
                          color: xplm ? XplmColors.cyan : NordColors.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.aboutChangelog[i],
                          style: TextStyle(color: secondary, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '—';
              final build = snapshot.data?.buildNumber ?? '';
              final label = build.isEmpty ? version : '$version ($build)';
              return Text(
                '${s.version} $label',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              );
            },
          ),
          const SizedBox(height: 18),
          _AboutPanel(
            surface: surface,
            border: border,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (!kIsWeb && (Platform.isWindows || Platform.isAndroid))
                  _AboutLink(
                    title: s.checkUpdates,
                    onTap: () => checkForAppUpdate(context, manual: true),
                  ),
                _AboutLink(
                  title: s.aboutOpenSite,
                  subtitle: AppBrand.current.host,
                  onTap: () => launchUrl(
                    Uri.parse(AppBrand.current.siteUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _AboutLink(
                  title: s.terms,
                  subtitle: '${AppBrand.current.host}/terms',
                  onTap: () => launchUrl(
                    Uri.parse(AppBrand.current.termsUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _AboutLink(
                  title: s.privacy,
                  subtitle: '${AppBrand.current.host}/privacy',
                  onTap: () => launchUrl(
                    Uri.parse(AppBrand.current.privacyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _AboutLink(
                  title: s.support,
                  subtitle: s.supportSoon,
                  onTap: () {
                    final channel = AppBrand.current.channelUrl;
                    final uri = channel != null
                        ? Uri.parse(channel)
                        : Uri(
                            scheme: 'mailto',
                            path: AppBrand.current.supportEmail,
                          );
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (AppBrand.current.isXplm) {
      return XplmHtmlPage(title: s.about, child: scaffold.body!);
    }
    return NordBackground(child: scaffold);
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({
    required this.child,
    required this.surface,
    required this.border,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color surface;
  final Color border;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.last = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(title),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: TextStyle(color: muted, fontSize: 13)),
          trailing: Icon(Icons.chevron_right, color: muted),
          onTap: onTap,
        ),
        if (!last) Divider(height: 1, color: border.withValues(alpha: 0.7)),
      ],
    );
  }
}
