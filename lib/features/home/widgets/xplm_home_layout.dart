import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/core/services/server_latency_monitor.dart';
import 'package:pulse_vpn/features/locations/country_picker_screen.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_codex_widgets.dart';

import 'xplm_home_scene.dart';

/// X-PLM home. All actions and live values come from the VPN controller.
class XplmHomeLayout extends StatelessWidget {
  const XplmHomeLayout({
    super.key,
    required this.onConnectPressed,
    required this.onOpenProfile,
    this.topBanner,
  });

  final Future<void> Function() onConnectPressed;
  final VoidCallback onOpenProfile;
  final Widget? topBanner;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final livePings = context.watch<ServerLatencyMonitor?>();
    final connected = controller.isConnected;
    final busy = controller.isBusy;

    String cta;
    if (controller.connectionState == VpnConnectionState.error) {
      cta = s.retry;
    } else if (controller.connectionState == VpnConnectionState.connecting) {
      cta = s.connecting;
    } else if (controller.connectionState == VpnConnectionState.disconnecting) {
      cta = s.disconnecting;
    } else if (connected) {
      cta = s.disconnect;
    } else if (controller.subscriptionLoadFailed) {
      cta = s.retry;
    } else if (controller.needsLink) {
      cta = s.account;
    } else {
      cta = s.connect;
    }

    final node = controller.connectedNode;
    final selected = controller.selectedLocation;
    final effective = controller.effectiveLocation;

    final locationLabel = connected
        ? (node?.countryName ?? (effective.isAuto ? s.auto : effective.nameRu))
        : (selected.isAuto ? s.auto : selected.nameRu);
    final locationCode = connected
        ? (node?.countryCode ??
              (effective.isAuto ? 'AUTO' : effective.countryCode))
        : selected.countryCode;

    var locationPing = -1;
    if (!selected.isAuto && selected.latencyMs >= 0) {
      locationPing = selected.latencyMs;
    }
    if (connected && !effective.isAuto && effective.latencyMs >= 0) {
      locationPing = effective.latencyMs;
    }
    final measuredPing = controller.lastProbeResults?[locationLabel];
    if (measuredPing != null) locationPing = measuredPing;
    if (locationPing < 0 &&
        (connected ? node == null && effective.isAuto : selected.isAuto)) {
      final pings = controller.locations
          .where((l) => !l.isAuto && l.latencyMs >= 0)
          .map((l) => l.latencyMs);
      if (pings.isNotEmpty) {
        locationPing = pings.reduce((a, b) => a < b ? a : b);
      }
    }

    final pingCountryId = connected
        ? (node?.countryId ?? effective.id)
        : selected.id;
    final autoPing = pingCountryId == 'auto';
    final liveValue = autoPing
        ? livePings?.bestPing
        : livePings?.pingFor(pingCountryId);
    if (livePings != null) locationPing = liveValue ?? -1;
    final pingMeasuring =
        livePings != null &&
        liveValue == null &&
        (autoPing ? livePings.isMeasuring : livePings.isPending(pingCountryId));

    final account = controller.account;
    final expiry = account.hasAccess && controller.hasExpiry
        ? 'до ${_fmtDate(account.accessExpiresAt)}'
        : (account.hasAccess ? 'активна' : 'Нет активной подписки');

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'XplmArial', fontSize: 14),
      child: ColoredBox(
        color: XplmColors.paper,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _HomeHeader(
                      onMenu: () {
                        if (XplmTabNavigation.openInTab(
                          context,
                          3,
                          const SettingsScreen(),
                        )) {
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      onBell: onOpenProfile,
                    ),
                  ),
                  Expanded(
                    child:
                        controller.linkState == SubscriptionLinkState.loading &&
                            !controller.isLoginWaiting &&
                            controller.profile == null
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                            children: [
                              if (topBanner != null) ...[
                                topBanner!,
                                const SizedBox(height: 8),
                              ],
                              SizedBox(
                                height:
                                    (MediaQuery.sizeOf(context).height * 0.28)
                                        .clamp(170.0, 260.0),
                                child: OverflowBox(
                                  maxWidth: MediaQuery.sizeOf(
                                    context,
                                  ).width.clamp(0.0, 440.0),
                                  child: XplmHomeScene(
                                    connected: connected,
                                    busy: busy,
                                  ),
                                ),
                              ),
                              _ConnectionBlock(
                                connected: connected,
                                busy: busy,
                                label: connected
                                    ? 'Подключено'
                                    : (busy ? cta : 'Отключено'),
                                description: connected
                                    ? 'Ваш интернет защищён'
                                    : (busy
                                          ? (controller.connectionState ==
                                                    VpnConnectionState
                                                        .disconnecting
                                                ? 'Завершаем защищённое соединение'
                                                : 'Устанавливаем защищённое соединение')
                                          : 'Нажмите, чтобы подключиться'),
                              ),
                              const SizedBox(height: 23),
                              _ServerCard(
                                countryCode: locationCode,
                                title: locationLabel,
                                subtitle:
                                    !connected && selected.isAuto
                                    ? s.bestServerAuto
                                    : null,
                                pingMs: locationPing,
                                measuring: pingMeasuring,
                                onPingPressed: livePings == null
                                    ? null
                                    : () => livePings.refresh(
                                        countryId: autoPing
                                            ? null
                                            : pingCountryId,
                                      ),
                                onTap: () {
                                  if (XplmTabNavigation.go(context, 1)) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const CountryPickerScreen(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 21),
                              _HomePrimaryButton(
                                label: cta,
                                height: 54,
                                fontSize: 18,
                                busy: busy,
                                icon: Icons.power_settings_new_rounded,
                                onPressed: busy
                                    ? null
                                    : () => onConnectPressed(),
                              ),
                              const SizedBox(height: 17),
                              _HomeGlass(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  14,
                                ),
                                child: Column(
                                  children: [
                                    _UsageRow(
                                      leading: const Text(
                                        '∞',
                                        style: TextStyle(
                                          fontSize: 32,
                                          height: 0.8,
                                          color: Color(0xFF03BDFF),
                                          shadows: [
                                            Shadow(
                                              color: Color(0xFF00A2FF),
                                              blurRadius: 7,
                                            ),
                                          ],
                                        ),
                                      ),
                                      caption: 'Трафик',
                                      value: 'Безлимитный',
                                    ),
                                    const SizedBox(height: 12),
                                    _UsageRow(
                                      leading: const Icon(
                                        Icons.schedule_rounded,
                                        color: Color(0xFF00A7EB),
                                        size: 25,
                                      ),
                                      caption: account.hasAccess
                                          ? 'Подписка активна'
                                          : 'Подписка',
                                      value: expiry,
                                      valueNormal: true,
                                    ),
                                  ],
                                ),
                              ),
                              if (connected) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${controller.sessionLabel}   ↓ ${_fmt(controller.downloadBytesPerSec)}   ↑ ${_fmt(controller.uploadBytesPerSec)}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: XplmColors.ink3,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onMenu, required this.onBell});

  final VoidCallback onMenu;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 65,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Tooltip(
              message: 'Настройки',
              child: XplmRoundIconButton(
                onTap: onMenu,
                icon: Icons.menu_rounded,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: MediaQuery.withNoTextScaling(
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'XPLM',
                      style: TextStyle(
                        fontFamily: 'XplmArial',
                        fontSize: 30,
                        height: .85,
                        letterSpacing: -1,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFCFEBFF),
                        shadows: [
                          Shadow(
                            color: Color(0xFF5186A5),
                            offset: Offset(0, 2),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'VPN',
                      style: TextStyle(
                        fontFamily: 'XplmArial',
                        fontSize: 26,
                        height: .85,
                        letterSpacing: 1,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF008DD1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Tooltip(
              message: 'Профиль',
              child: XplmRoundIconButton(
                onTap: onBell,
                icon: Icons.notifications_none_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBlock extends StatelessWidget {
  const _ConnectionBlock({
    required this.connected,
    required this.busy,
    required this.label,
    required this.description,
  });

  final bool connected;
  final bool busy;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final checkColor = connected
        ? XplmColors.ok
        : (busy ? XplmColors.cyan : const Color(0xFF657A8D));
    final duration = Duration(
      milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 220,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: duration,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checkColor,
                boxShadow: [
                  BoxShadow(
                    color: checkColor.withValues(alpha: 0.38),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                connected
                    ? Icons.check_rounded
                    : (busy
                          ? Icons.more_horiz_rounded
                          : Icons.power_settings_new_rounded),
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: AnimatedSwitcher(
                duration: duration,
                child: Text(
                  label,
                  key: ValueKey(label),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 31 / 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            height: 16 / 14,
            color: Color(0xFFB4C3D5),
          ),
        ),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.countryCode,
    required this.title,
    required this.pingMs,
    required this.onTap,
    this.subtitle,
    this.measuring = false,
    this.onPingPressed,
  });

  final String countryCode;
  final String title;
  final String? subtitle;
  final int pingMs;
  final VoidCallback onTap;
  final bool measuring;
  final VoidCallback? onPingPressed;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: _HomeGlass(
          padding: const EdgeInsets.fromLTRB(17, 12, 17, 12),
          child: Column(
            children: [
              SizedBox(
                height: hasSubtitle ? null : 34,
                child: Row(
                  children: [
                    if (countryCode.toLowerCase() == 'auto')
                      const CircleAvatar(
                        radius: 15,
                        backgroundColor: Color(0xFF06416A),
                        child: Icon(
                          Icons.public_rounded,
                          size: 21,
                          color: XplmColors.cyan,
                        ),
                      )
                    else
                      XplmFlagCircle(code: countryCode, size: 30),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          if (hasSubtitle) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF91A5BF),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Text(
                      '›',
                      style: TextStyle(
                        color: Color(0xFF92ADCA),
                        fontSize: 25,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              const Divider(height: 1, color: Color(0xFF19304C)),
              const SizedBox(height: 7),
              _HomePingLine(
                pingMs: pingMs,
                measuring: measuring,
                onRefresh: onPingPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.leading,
    required this.caption,
    required this.value,
    this.valueNormal = false,
  });

  final Widget leading;
  final String caption;
  final String value;
  final bool valueNormal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 32, child: Center(child: leading)),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFAFC1D9),
                  height: 1.25,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.25,
                  color: const Color(0xFFF0F6FF),
                  fontWeight: valueNormal ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _fmt(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec Б/с';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} КБ/с';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} МБ/с';
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// Kept for tests / previews that still import the old name.
class XplmGlobeShield extends StatelessWidget {
  const XplmGlobeShield({
    super.key,
    required this.connected,
    required this.busy,
  });

  final bool connected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 158,
      child: Stack(
        children: [
          const Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: XplmEarthBackdrop(),
          ),
          Center(child: XplmHeroShield(connected: connected || busy)),
        ],
      ),
    );
  }
}

/// CSS gradients, borders, and inset highlights from the HTML reference.
class _HtmlSurfacePainter extends CustomPainter {
  const _HtmlSurfacePainter({this.primary = false});
  final bool primary;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(primary ? 25 : 17);
    final shape = RRect.fromRectAndRadius(rect.deflate(.5), radius);
    canvas.drawRRect(
      shape,
      Paint()
        ..color = primary ? const Color(0x30007CFF) : const Color(0x16008EFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, primary ? 8 : 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader =
            (primary
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF00ADFF), Color(0xFF0074F6)],
                      )
                    : const LinearGradient(
                        begin: Alignment(-.819, -.574),
                        end: Alignment(.819, .574),
                        colors: [
                          Color(0xFF06203C),
                          Color(0xFF06172D),
                          Color(0xFF092B50),
                        ],
                        stops: [0, .55, 1],
                      ))
                .createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(4).shift(const Offset(0, 2)),
        radius,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = primary ? const Color(0x448DEEFF) : const Color(0x281A84DC)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = primary ? const Color(0xFF008CFF) : const Color(0xFF1B466B),
    );
  }

  @override
  bool shouldRepaint(covariant _HtmlSurfacePainter oldDelegate) =>
      primary != oldDelegate.primary;
}

class _HomeGlass extends StatelessWidget {
  const _HomeGlass({required this.child, required this.padding});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _HtmlSurfacePainter(),
    child: Padding(padding: padding.add(const EdgeInsets.all(1)), child: child),
  );
}

class _HomePrimaryButton extends StatelessWidget {
  const _HomePrimaryButton({
    required this.label,
    required this.onPressed,
    required this.busy,
    required this.icon,
    this.height = 54,
    this.fontSize = 18,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;
  final double height;
  final double fontSize;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _HtmlSurfacePainter(primary: true),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(25),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      value: MediaQuery.of(context).disableAnimations
                          ? .75
                          : null,
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 24, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

class _HomePingLine extends StatelessWidget {
  const _HomePingLine({
    required this.pingMs,
    required this.measuring,
    this.onRefresh,
  });
  final int pingMs;
  final bool measuring;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 27,
    child: Tooltip(
      message: 'Обновить TCP-пинг сервера',
      child: InkWell(
        onTap: onRefresh,
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF24B5FF), size: 18),
            const SizedBox(width: 4),
            Text(
              measuring
                  ? 'Пинг: …'
                  : pingMs >= 0
                  ? 'Пинг: $pingMs ms'
                  : 'Пинг: —',
              style: const TextStyle(fontSize: 13, color: Color(0xFFC4D1E3)),
            ),
            const Spacer(),
            XplmSignalBars(latencyMs: pingMs),
          ],
        ),
      ),
    ),
  );
}
