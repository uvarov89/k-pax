import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';
import 'package:pulse_vpn/core/state/vpn_controller.dart';

/// Handles `kpax://` links from the site, bot, and payment return.
class DeepLinkService {
  DeepLinkService(this._controller);

  final VpnController _controller;
  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    if (kIsWeb) return;
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) await handle(initial);
      _sub = _links.uriLinkStream.listen((uri) {
        unawaited(handle(uri));
      });
    } catch (_) {
      // Missing plugin in unit tests / unsupported platforms.
    }
  }

  Future<void> handle(Uri uri) async {
    if (uri.scheme != 'kpax') return;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'confirmed' || path == '/confirmed') {
      await _controller.onLoginConfirmedDeepLink();
      return;
    }
    if (host == 'paid' || path == '/paid') {
      await _controller.refreshAccessAfterPayment();
      return;
    }

    final subParam = uri.queryParameters['url'] ?? uri.queryParameters['sub'];
    if (subParam != null && subParam.isNotEmpty) {
      await _controller.submitSubscriptionLink(subParam);
      return;
    }

    if (host == 'sub' || path.startsWith('/s/') || path.startsWith('/sub/')) {
      final token = path.startsWith('/s/')
          ? path.substring(3)
          : path.startsWith('/sub/')
              ? path.substring(5)
              : (uri.queryParameters['token'] ?? '');
      if (token.isNotEmpty) {
        final link = 'https://sub.k-pax.space/s/$token';
        if (kPaxSubscriptionUri(link) != null) {
          await _controller.submitSubscriptionLink(link);
        }
      }
      return;
    }

    final contact = uri.queryParameters['contact'];
    if (contact != null && contact.isNotEmpty) {
      await _controller.submitSubscriptionLink(contact);
    }
  }

  Future<void> dispose() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }
}
