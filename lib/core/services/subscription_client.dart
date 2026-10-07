import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/core/services/subscription_link.dart';

class SubscriptionClient {
  Future<FetchedSubscription> fetch(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'K-Pax');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 403 || body.contains('Подписка недействительна')) {
        throw const SubscriptionRejected();
      }
      if (response.statusCode != 200) {
        throw const HttpException('subscription');
      }
      return FetchedSubscription(
        body: body,
        userinfo: response.headers.value('subscription-userinfo'),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AppStartResult> startWithContact(String contact) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('https://k-pax.space/app/start'))
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode({'contact': contact.trim()})));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const HttpException('start');
      if (response.statusCode != 200) {
        return AppStartResult(
          created: false,
          publicId: '',
          expiresAt: 0,
          error: decoded['error']?.toString() ?? 'Не получилось выдать доступ.',
        );
      }
      final rawUrl = decoded['url']?.toString() ?? '';
      return AppStartResult(
        created: decoded['created'] == true,
        url: rawUrl.isEmpty ? null : kPaxSubscriptionUri(rawUrl),
        publicId: decoded['public_id']?.toString() ?? '',
        expiresAt: int.tryParse('${decoded['expires_at']}') ?? 0,
        active: decoded['active'] != false,
        channel: decoded['channel']?.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
