import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pulse_vpn/app/theme/xplm_colors.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class XplmAccountDetails extends StatefulWidget {
  const XplmAccountDetails({
    super.key,
    required this.controller,
    required this.contact,
    required this.submitting,
    required this.onSubmit,
    required this.onCancelLogin,
    required this.onOpenDevices,
    required this.subscriptions,
    required this.onLogout,
  });
  final VpnController controller;
  final TextEditingController contact;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancelLogin;
  final VoidCallback onOpenDevices;
  final Widget subscriptions;
  final VoidCallback onLogout;
  @override
  State<XplmAccountDetails> createState() => _XplmAccountDetailsState();
}

class _XplmAccountDetailsState extends State<XplmAccountDetails> {
  bool _adding = false;
  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || data?.text == null) return;
      widget.contact.text = data!.text!.trim();
      setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать буфер обмена')),
        );
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.controller.refreshServers();
      if (!mounted) return;
      final c = widget.controller;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(c.linkError ?? c.strings.serversUpdated)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.strings.linkOpenFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VpnController>();
    final s = c.strings;
    final owned = c.isKPaxSubscription;
    final loading =
        widget.submitting || c.linkState == SubscriptionLinkState.loading;
    final id = c.account.userId;
    final showId = owned && id.isNotEmpty && !id.startsWith('u_');
    final showForm =
        c.needsLink || c.isLoginWaiting || c.subscriptionUrl == null || _adding;
    final expiry = c.account.accessExpiresAt;
    final date =
        '${expiry.day.toString().padLeft(2, '0')}.${expiry.month.toString().padLeft(2, '0')}.${expiry.year}';
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: XplmColors.ink2,
        ),
      ),
    );
    return XplmHtmlPage(
      title: s.account,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          XplmHtmlGlass(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      c.hasAccess
                          ? Icons.verified_user_outlined
                          : Icons.person_outline_rounded,
                      size: 32,
                      color: c.hasAccess ? XplmColors.ok : XplmColors.cyan,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.hasAccess
                                ? c.subscriptionName
                                : (c.subscriptionUrl == null
                                      ? (s.isRu ? 'Вход в аккаунт' : 'Sign in')
                                      : (c.subscriptionLoadFailed
                                            ? s.accountSavedOffline
                                            : (s.isRu
                                                  ? 'Подписка не активна'
                                                  : 'Subscription inactive'))),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            c.hasAccess
                                ? (c.hasExpiry
                                      ? s.activeUntil(date)
                                      : owned
                                      ? (s.isRu
                                            ? 'Срок доступа уточняется'
                                            : 'Expiry not provided')
                                      : s.noExpiry)
                                : (c.subscriptionLoadFailed
                                      ? s.linkOpenFailed
                                      : (s.isRu
                                            ? 'Войдите или добавьте ссылку на подписку'
                                            : 'Sign in or add a subscription link')),
                            style: const TextStyle(
                              fontSize: 12,
                              color: XplmColors.ink2,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (showId) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          s.isRu
                              ? 'Номер аккаунта: $id'
                              : 'Account number: $id',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: s.isRu
                            ? 'Скопировать номер аккаунта'
                            : 'Copy account number',
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: id));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  s.isRu
                                      ? 'Номер аккаунта скопирован'
                                      : 'Account number copied',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (c.subscriptionLoadFailed) ...[
            const SizedBox(height: 14),
            XplmHtmlGlass(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.subscriptionNetworkFailed,
                    style: const TextStyle(
                      fontSize: 13,
                      color: XplmColors.ink2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  XplmHtmlButton(
                    label: s.retry,
                    busy: loading,
                    onPressed: loading ? null : () => c.reloadSubscription(),
                  ),
                ],
              ),
            ),
          ],
          if (showForm) ...[
            section(s.pasteLinkTitle),
            XplmHtmlGlass(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.pasteLinkBody,
                    style: const TextStyle(
                      fontSize: 13,
                      color: XplmColors.ink2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (c.isLoginWaiting) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.waitingEmailConfirm,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    if ((c.loginHint ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        c.loginHint!,
                        style: const TextStyle(
                          color: XplmColors.ink2,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: widget.onCancelLogin,
                      child: Text(s.cancelLogin),
                    ),
                  ] else ...[
                    TextField(
                      key: const ValueKey('account-contact'),
                      controller: widget.contact,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !loading && !c.isBusy,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (!loading && widget.contact.text.trim().isNotEmpty) {
                          widget.onSubmit();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: s.pasteLinkHint,
                        suffixIcon: IconButton(
                          tooltip: s.isRu ? 'Вставить' : 'Paste',
                          onPressed: loading ? null : _paste,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                      ),
                    ),
                    if (c.linkError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        c.linkError!,
                        style: const TextStyle(
                          color: Color(0xFFFFC1CC),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    XplmHtmlButton(
                      label: s.saveLink,
                      busy: loading,
                      onPressed:
                          loading ||
                              c.isBusy ||
                              widget.contact.text.trim().isEmpty
                          ? null
                          : widget.onSubmit,
                    ),
                    if (loading)
                      TextButton(
                        onPressed: widget.onCancelLogin,
                        child: Text(s.cancelLogin),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    s.lostAccessHelp,
                    style: const TextStyle(
                      fontSize: 12,
                      color: XplmColors.ink3,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (c.subscriptionUrl != null) ...[
            section(s.isRu ? 'Доступ и устройства' : 'Access & devices'),
            XplmHtmlGlass(
              child: Column(
                children: [
                  if (owned) ...[
                    ListTile(
                      key: const ValueKey('account-manage'),
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text(s.manageSubscription),
                      subtitle: Text(s.seePlans),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openPaywall(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const ValueKey('account-devices'),
                      leading: const Icon(Icons.devices_rounded),
                      title: Text(s.devices),
                      subtitle: Text(s.devicesHint),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: widget.onOpenDevices,
                    ),
                    const Divider(height: 1),
                  ] else if (c.providerWebPage != null) ...[
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text(s.providerSite),
                      subtitle: Text(s.providerSiteHint),
                      onTap: () => launchUrl(
                        c.providerWebPage!,
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    key: const ValueKey('account-refresh'),
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(s.refreshServers),
                    subtitle: Text(s.refreshServersHint),
                    trailing: c.isRefreshingServers
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: c.isRefreshingServers || c.isBusy ? null : _refresh,
                  ),
                ],
              ),
            ),
          ],
          if (c.subscriptions.isNotEmpty) ...[
            section(s.mySubscriptions),
            XplmHtmlGlass(
              padding: const EdgeInsets.all(16),
              child: widget.subscriptions,
            ),
          ],
          if (!showForm) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('account-add'),
              onPressed: c.isBusy ? null : () => setState(() => _adding = true),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(
                s.isRu
                    ? 'Добавить другую подписку'
                    : 'Add another subscription',
              ),
            ),
          ],
          if (c.subscriptionUrl != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const ValueKey('account-logout'),
              onPressed: loading || c.isBusy ? null : widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: Text(s.isRu ? 'Выйти из аккаунта' : 'Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}
