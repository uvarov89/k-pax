import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/core/models/subscription.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

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

  Future<void> _openDevices(BuildContext context, VpnController controller) async {
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(s.devicesHint, style: TextStyle(color: muted, height: 1.35)),
                    const SizedBox(height: 12),
                    if (c.isLoadingDevices)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (c.devicesError != null)
                      Text(c.devicesError!, style: const TextStyle(color: Color(0xFFFFC1CC)))
                    else if (c.devices.isEmpty)
                      Text(s.devicesEmpty, style: TextStyle(color: muted))
                    else
                      ...c.devices.map(
                        (device) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(device.label.isEmpty ? s.devices : device.label),
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
                                  content: Text(ok ? s.devicesKicked : s.devicesLoadFailed),
                                ),
                              );
                            },
                            child: Text(s.devicesKick),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: c.isLoadingDevices ? null : () => c.loadDevices(),
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
        content: Text(number.isEmpty ? s.linkReadyBody : '$number\n\n${s.linkReadyBody}'),
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VpnController>();
    final s = controller.strings;
    final account = controller.account;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final surface =
        isDark ? NordColors.surface : NordColors.lightSurface;
    final border = isDark ? NordColors.border : NordColors.lightBorder;
    final date =
        '${account.accessExpiresAt.day.toString().padLeft(2, '0')}.'
        '${account.accessExpiresAt.month.toString().padLeft(2, '0')}.'
        '${account.accessExpiresAt.year}';
    final kpax = controller.isKPaxSubscription;
    final showId = kpax && account.userId.isNotEmpty && !account.userId.startsWith('u_');

    return NordBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.account),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(s.pasteLinkBody, style: TextStyle(color: muted, height: 1.6)),
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
                        Text(controller.loginHint!, style: TextStyle(color: muted, height: 1.35)),
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
                          onPressed: controller.linkState == SubscriptionLinkState.loading
                              ? null
                              : () => _submit(controller),
                          child: Text(s.saveLink),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(s.lostAccessHelp, style: TextStyle(color: muted, height: 1.4)),
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
                    account.hasAccess ? controller.subscriptionName : s.noAccessYet,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showId) ...[
                    const SizedBox(height: 4),
                    Text('${s.userId}: ${account.userId}',
                        style: TextStyle(color: muted, fontSize: 13)),
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
                RegExp('^${RegExp.escape(AppBrand.current.accountPrefix)}-\\d{5,8}\$')
                    .hasMatch(account.userId)) ...[
              const SizedBox(height: 12),
              _Card(
                surface: surface,
                border: border,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.referralTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(s.referralBody, style: TextStyle(color: muted, height: 1.45)),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.linkCopied)),
                          );
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
                        subtitle:
                            Text(s.devicesHint, style: TextStyle(color: muted)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDevices(context, controller),
                      ),
                    if (kpax) const Divider(height: 1),
                  ] else if (controller.providerWebPage != null) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.providerSite),
                      subtitle: Text(s.providerSiteHint, style: TextStyle(color: muted)),
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
                    subtitle: Text(s.refreshServersHint, style: TextStyle(color: muted)),
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
                            final message = controller.linkError ?? s.serversUpdated;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({required this.controller, required this.muted});

  final VpnController controller;
  final Color muted;

  Future<void> _confirmRemove(BuildContext context, SavedSubscription item) async {
    final s = controller.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeSubscription),
        content: Text(s.removeSubscriptionBody(controller.subscriptionLabel(item))),
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
    final busy = controller.isBusy || controller.linkState == SubscriptionLinkState.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.mySubscriptions,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(s.mySubscriptionsHint, style: TextStyle(color: muted, height: 1.45)),
        const SizedBox(height: 8),
        for (final item in controller.subscriptions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item.url == controller.subscriptionUrl
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: item.url == controller.subscriptionUrl ? NordColors.accent : muted,
            ),
            title: Text(
              controller.subscriptionLabel(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.url == controller.subscriptionUrl
                ? Text(s.activeSubscription, style: TextStyle(color: muted, fontSize: 13))
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? NordColors.accentDim.withValues(alpha: 0.35) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent ? NordColors.accent : NordColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accent ? NordColors.accent : NordColors.textSecondary,
        ),
      ),
    );
  }
}
