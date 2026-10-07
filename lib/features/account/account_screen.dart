import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pulse_vpn/core/state/vpn_controller.dart';
import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/paywall/paywall_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _contact = TextEditingController();
  final _entryKey = GlobalKey();
  final _fieldFocus = FocusNode();

  @override
  void dispose() {
    _contact.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _focusEntry() {
    final target = _entryKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, alignment: 0.05, duration: const Duration(milliseconds: 250));
    }
    _fieldFocus.requestFocus();
  }

  Future<void> _openRestore(String channel) async {
    final uri = channel == 'email'
        ? Uri.parse(
            'mailto:support@k-pax.space?subject=${Uri.encodeComponent('Восстановление доступа K-Pax')}&body=${Uri.encodeComponent('Прошу вернуть ссылку доступа.')}',
          )
        : Uri.parse('https://t.me/KPax_Space_bot?start=restore');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(channel == 'email' ? 'support@k-pax.space' : '@KPax_Space_bot')),
      );
    }
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
    final showId = account.userId.isNotEmpty && !account.userId.startsWith('u_');
    final restoring = controller.restoreChannel;

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Card(
              key: _entryKey,
                surface: surface,
                border: border,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.pasteLinkTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(s.pasteLinkBody, style: TextStyle(color: muted, height: 1.35)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _contact,
                      focusNode: _fieldFocus,
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
                    if (restoring == 'email' || restoring == 'telegram') ...[
                      const SizedBox(height: 8),
                      Text(
                        restoring == 'email' ? s.restoreHintEmail : s.restoreHintTelegram,
                        style: TextStyle(color: muted, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _openRestore(restoring!),
                          child: Text(s.restoreAccess),
                        ),
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
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _Card(
              surface: surface,
              border: border,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.hasAccess ? s.planName : s.noAccessYet,
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
                          label: s.daysLeft(account.daysRemaining),
                          accent: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.activeUntil(date),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              surface: surface,
              border: border,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.manageSubscription),
                    subtitle: Text(s.seePlans, style: TextStyle(color: muted)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPaywall(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.devices),
                    subtitle:
                        Text(s.devicesStub, style: TextStyle(color: muted)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.replaceLink),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: _focusEntry,
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

class _Card extends StatelessWidget {
  const _Card({
    super.key,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
