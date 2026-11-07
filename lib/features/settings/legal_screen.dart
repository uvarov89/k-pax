import 'package:flutter/material.dart';
import 'package:pulse_vpn/app/brand/app_brand.dart';

import 'package:pulse_vpn/app/theme/nord_signal_theme.dart';
import 'package:pulse_vpn/features/xplm/widgets/xplm_html_widgets.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? NordColors.textMuted : NordColors.lightTextMuted;
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        itemCount: paragraphs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) => Text(
          paragraphs[index],
          style: TextStyle(color: muted, height: 1.6, fontSize: 15),
        ),
      ),
    );
    if (AppBrand.current.isXplm) {
      return XplmHtmlPage(title: title, child: scaffold.body!);
    }
    return NordBackground(child: scaffold);
  }
}
