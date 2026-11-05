import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/settings/about_screen.dart';
import 'package:pulse_vpn/features/settings/settings_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    this.embeddedInShell = false,
    this.accountDetails = false,
  });

  final bool embeddedInShell;
  final bool accountDetails;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _contact = TextEditingController();

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _openDevices(
    BuildContext context,
    VpnController controller,
  ) async {
    await controller.loadDevices();
    if (!context.mounted) return;
    final s = controller.strings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer<VpnController>(
          builder: (context, c, _) {
            final muted = Theme.of(context).brightness == Brightness.dark
                ? NordColors.textMuted
                : NordColors.lightTextMuted;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.devices,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.devicesHint,
                      style: TextStyle(color: muted, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    if (c.isLoadingDevices)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (c.devicesError != null)
                      Text(
                        c.devicesError!,
                        style: const TextStyle(color: Color(0xFFFFC1CC)),
                      )
                    else if (c.devices.isEmpty)
                      Text(s.devicesEmpty, style: TextStyle(color: muted))
                    else
                      ...c.devices.map(
                        (device) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            device.label.isEmpty ? s.devices : device.label,
                          ),
                          subtitle: Text(
                            device.detail,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              final ok = await c.kickDevice(device.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? s.devicesKicked : s.devicesLoadFailed,
                                  ),
                                ),
                              );
                            },
                            child: Text(s.devicesKick),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: c.isLoadingDevices
                          ? null
                          : () => c.loadDevices(),
                      child: Text(s.devicesRefresh),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit(VpnController controller) async {
    await controller.submitSubscriptionLink(_contact.text);
    if (!mounted) return;
    final url = controller.oneTimeUrl;
    if (url == null) return;
    final s = controller.strings;
    final number = controller.oneTimeNumber ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(s.linkReadyTitle),
        content: Text(
          number.isEmpty ? s.linkReadyBody : '$number\n\n${s.linkReadyBody}',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
            },
            child: Text(s.copyLink),
          ),
          TextButton(
            onPressed: () {
              controller.clearOneTimeLink();
              Navigator.of(context).pop();
            },
            child: Text(s.continueLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(VpnController controller) async {
    final s = controller.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeSubscription),
        content: Text(s.removeSubscriptionBody(controller.subscriptionName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (ok == true) await controller.forgetSubscriptionLink();
  }

  void _showTraffic(VpnController controller) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Consumer<VpnController>(
            builder: (context, controller, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Статистика трафика',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text('Время подключения: ${controller.sessionLabel}'),
                const SizedBox(height: 8),
                Text('Загрузка: ${controller.downloadBytesPerSec} Б/с'),
                Text('Отправка: ${controller.uploadBytesPerSec} Б/с'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildXplmProfile(VpnController controller) {
    void account() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AccountScreen(accountDetails: true),
      ),
    );
    void settings() => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    final channel = AppBrand.current.channelUrl;
    return XplmHtmlPage(
      title: 'Настройки',
      showBack: !widget.embeddedInShell,
      action: XplmHtmlIconButton(
        icon: Icons.settings_outlined,
        tooltip: 'Параметры',
        onPressed: settings,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          const _XplmProfileHeader(),
          const SizedBox(height: 25),
          if (controller.needsLink) ...[
            XplmHtmlButton(
              label: 'Войти или добавить подписку',
              onPressed: account,
            ),
            const SizedBox(height: 16),
          ],
          XplmHtmlGlass(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                _XplmMenuRow(
                  icon: Icons.notifications_none_rounded,
                  label: 'Уведомления',
                  trailing: controller.appSettings.notificationsEnabled
                      ? 'Вкл.'
                      : 'Выкл.',
                  onTap: () => controller.updateAppSettings(
                    controller.appSettings.copyWith(
                      notificationsEnabled:
                          !controller.appSettings.notificationsEnabled,
                    ),
                  ),
                ),
                _XplmMenuRow(
                  icon: Icons.shield_outlined,
                  label: 'Безопасность',
                  onTap: settings,
                ),
                _XplmMenuRow(
                  icon: Icons.bar_chart_rounded,
                  label: 'Статистика трафика',
                  barsIcon: true,
                  onTap: () => _showTraffic(controller),
                ),
                _XplmMenuRow(
                  icon: Icons.headphones_rounded,
                  label: 'Поддержка',
                  onTap: () => launchUrl(
                    Uri.parse('mailto:${AppBrand.current.supportEmail}'),
                  ),
                ),
                _XplmMenuRow(
                  icon: Icons.info_outline_rounded,
                  label: 'О приложении',
                  divider: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (channel != null) ...[
            const SizedBox(height: 18),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () => launchUrl(
                  Uri.parse(channel),
                  mode: LaunchMode.externalApplication,
                ),
                child: XplmHtmlGlass(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.send_rounded,
                        size: 38,
                        color: Color(0xFF00BAFF),
                        shadows: [
                          Shadow(color: Color(0xFF009DFF), blurRadius: 9),
                        ],
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Присоединяйтесь\nк нашему Telegram-каналу',
                              style: TextStyle(fontSize: 14, height: 1.35),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Новости, акции и полезные\nсоветы',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Color(0xFFA3B3CA),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: Color(0xFF8AA4C2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 45,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: XplmColors.ink,
                backgroundColor: const Color(0x800B1A2C),
                side: const BorderSide(color: Color(0xFF66819D)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                'Выйти',
                style: TextStyle(fontFamily: 'XplmArial', fontSize: 14),
              ),
              onPressed: controller.subscriptionUrl == null
                  ? null
                  : () => _confirmLogout(controller),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: account,
            child: const Text(
              'Аккаунт и подписки',
              style: TextStyle(fontFamily: 'XplmArial'),
            ),
          ),
        ],
      ),
    );
  }

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
    final surface = xplm
        ? XplmColors.surface
        : (isDark ? NordColors.surface : NordColors.lightSurface);
    final border = xplm
        ? XplmColors.line
        : (isDark ? NordColors.border : NordColors.lightBorder);
    final date =
        '${account.accessExpiresAt.day.toString().padLeft(2, '0')}.'
        '${account.accessExpiresAt.month.toString().padLeft(2, '0')}.'
        '${account.accessExpiresAt.year}';
    final kpax = controller.isKPaxSubscription;
    final showId =
        kpax && account.userId.isNotEmpty && !account.userId.startsWith('u_');

    if (xplm && !widget.accountDetails) return _buildXplmProfile(controller);

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.account),
        automaticallyImplyLeading: !widget.embeddedInShell,
        leading: widget.embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: xplm
            ? [
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.settings_rounded,
                    color: XplmColors.cyan.withValues(alpha: 0.9),
                  ),
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _Card(
            surface: surface,
            border: border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.pasteLinkTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  s.pasteLinkBody,
                  style: TextStyle(color: muted, height: 1.6),
                ),
                if (controller.isLoginWaiting) ...[
                  const SizedBox(height: 16),
                  Text(
                    controller.loginChannel == 'telegram'
                        ? s.waitingTelegramConfirm
                        : s.waitingEmailConfirm,
                    style: TextStyle(color: muted, height: 1.45),
                  ),
                  if ((controller.loginHint ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.loginHint!,
                      style: TextStyle(color: muted, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (controller.loginChannel == 'telegram' &&
                      (controller.loginBotUrl ?? '').isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => launchUrl(
                          Uri.parse(controller.loginBotUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(s.openBotConfirm),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: controller.cancelLogin,
                      child: Text(s.cancelLogin),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contact,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: s.pasteLinkHint,
                      filled: true,
                    ),
                  ),
                  if (controller.linkError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.linkError!,
                      style: const TextStyle(color: Color(0xFFFFC1CC)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          controller.linkState == SubscriptionLinkState.loading
                          ? null
                          : () => _submit(controller),
                      child: Text(s.saveLink),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.lostAccessHelp,
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          if (controller.subscriptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Card(
              surface: surface,
              border: border,
              child: _SubscriptionList(controller: controller, muted: muted),
            ),
          ],
          const SizedBox(height: 12),
          _Card(
            surface: surface,
            border: border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.hasAccess
                      ? controller.subscriptionName
                      : s.noAccessYet,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showId) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${s.userId}: ${account.userId}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
                if (account.hasAccess) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(
                        label: controller.planLabel(account.plan),
                        accent: true,
                      ),
                      _Chip(
                        label: controller.hasExpiry
                            ? s.daysLeft(account.daysRemaining)
                            : s.noExpiry,
                        accent: false,
                      ),
                    ],
                  ),
                  if (controller.hasExpiry) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.activeUntil(date),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (kpax &&
              RegExp(
                '^${RegExp.escape(AppBrand.current.accountPrefix)}-\\d{5,8}\$',
              ).hasMatch(account.userId)) ...[
            const SizedBox(height: 12),
            _Card(
              surface: surface,
              border: border,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.referralTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.referralBody,
                    style: TextStyle(color: muted, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    s.inviteLink(account.userId),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: s.inviteLink(account.userId)),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(s.linkCopied)));
                      },
                      child: Text(s.copyLink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Card(
            surface: surface,
            border: border,
            child: Column(
              children: [
                if (kpax || controller.needsLink) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.manageSubscription),
                    subtitle: Text(s.seePlans, style: TextStyle(color: muted)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPaywall(context),
                  ),
                  const Divider(height: 1),
                  if (kpax)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.devices),
                      subtitle: Text(
                        s.devicesHint,
                        style: TextStyle(color: muted),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDevices(context, controller),
                    ),
                  if (kpax) const Divider(height: 1),
                ] else if (controller.providerWebPage != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.providerSite),
                    subtitle: Text(
                      s.providerSiteHint,
                      style: TextStyle(color: muted),
                    ),
                    trailing: Icon(Icons.open_in_new, color: muted, size: 20),
                    onTap: () => launchUrl(
                      controller.providerWebPage!,
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.refreshServers),
                  subtitle: Text(
                    s.refreshServersHint,
                    style: TextStyle(color: muted),
                  ),
                  trailing: controller.isRefreshingServers
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh, color: muted),
                  onTap: controller.isRefreshingServers
                      ? null
                      : () async {
                          await controller.refreshServers();
                          if (!context.mounted) return;
                          final message =
                              controller.linkError ?? s.serversUpdated;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (xplm) return XplmHtmlPage(title: s.account, child: scaffold.body!);
    if (widget.embeddedInShell) return scaffold;
    return NordBackground(child: scaffold);
  }
}

class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({required this.controller, required this.muted});

  final VpnController controller;
  final Color muted;

  Future<void> _confirmRemove(
    BuildContext context,
    SavedSubscription item,
  ) async {
    final s = controller.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeSubscription),
        content: Text(
          s.removeSubscriptionBody(controller.subscriptionLabel(item)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (ok == true) await controller.removeSubscription(item.url);
  }

  @override
  Widget build(BuildContext context) {
    final s = controller.strings;
    final busy =
        controller.isBusy ||
        controller.linkState == SubscriptionLinkState.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.mySubscriptions,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          s.mySubscriptionsHint,
          style: TextStyle(color: muted, height: 1.45),
        ),
        const SizedBox(height: 8),
        for (final item in controller.subscriptions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item.url == controller.subscriptionUrl
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: item.url == controller.subscriptionUrl
                  ? NordColors.accent
                  : muted,
            ),
            title: Text(
              controller.subscriptionLabel(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.url == controller.subscriptionUrl
                ? Text(
                    s.activeSubscription,
                    style: TextStyle(color: muted, fontSize: 13),
                  )
                : null,
            trailing: IconButton(
              tooltip: s.removeSubscription,
              icon: Icon(Icons.delete_outline, color: muted),
              onPressed: busy ? null : () => _confirmRemove(context, item),
            ),
            onTap: busy ? null : () => controller.switchSubscription(item.url),
          ),
      ],
    );
  }
}

class _XplmProfileHeader extends StatelessWidget {
  const _XplmProfileHeader();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 95,
        width: 95,
        child: OverflowBox(
          maxWidth: 139,
          maxHeight: 139,
          child: Image.asset(
            'assets/brand/xplm_profile_logo.png',
            width: 139,
            height: 139,
            excludeFromSemantics: true,
          ),
        ),
      ),
      const SizedBox(height: 13),
      const Text(
        'XPLM VPN',
        style: TextStyle(
          fontSize: 21,
          height: 24 / 21,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 3),
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) => Text(
          'v${snapshot.data?.version ?? '…'}',
          style: const TextStyle(
            color: Color(0xFF96AAC3),
            fontSize: 13,
            height: 15 / 13,
          ),
        ),
      ),
    ],
  );
}

class _XplmMenuRow extends StatelessWidget {
  const _XplmMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.barsIcon = false,
    this.divider = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final bool barsIcon;
  final bool divider;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: divider
              ? const Border(bottom: BorderSide(color: Color(0xFF1C314C)))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: barsIcon
                  ? const Color(0xFF00ADF5)
                  : const Color(0xFF8DBBE9),
              shadows: const [Shadow(color: Color(0xFF168CDD), blurRadius: 5)],
            ),
            const SizedBox(width: 17),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(color: Color(0xFF38A4DC), fontSize: 13),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Color(0xFF8AA4C2),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.surface,
    required this.border,
    required this.child,
  });

  final Color surface;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: xplm ? 0.9 : 1),
        borderRadius: BorderRadius.circular(xplm ? 18 : 16),
        border: Border.all(
          color: xplm ? XplmColors.cyan.withValues(alpha: 0.32) : border,
        ),
        boxShadow: xplm
            ? [
                BoxShadow(
                  color: XplmColors.cyan.withValues(alpha: 0.14),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.accent});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final xplm = AppBrand.current.isXplm;
    final accentColor = xplm ? XplmColors.cyan : NordColors.accent;
    final accentFill = xplm
        ? XplmColors.accentSoft
        : NordColors.accentDim.withValues(alpha: 0.35);
    final mutedBorder = xplm ? XplmColors.line : NordColors.border;
    final mutedText = xplm ? XplmColors.ink2 : NordColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? accentFill : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent ? accentColor : mutedBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accent ? accentColor : mutedText,
        ),
      ),
    );
  }
}
