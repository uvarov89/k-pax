import 'dart:convert';
import 'dart:io';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/services/subscription_link.dart';

class SubscriptionClient {
  String get _ua => AppBrand.current.appName;

  Future<FetchedSubscription> fetch(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
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
        publicId: AppBrand.current.isXplm
            ? (response.headers.value('x-xplm-id') ??
                response.headers.value('x-kpax-id'))
            : (response.headers.value('x-kpax-id') ??
                response.headers.value('x-xplm-id')),
        title: profileTitle(response.headers.value('profile-title')),
        webPage: providerPage(
          response.headers.value('profile-web-page-url') ?? response.headers.value('support-url'),
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, Object?> payload) async {
    final client = HttpClient();
    try {
      final bytes = utf8.encode(jsonEncode(payload));
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          return {
            'status': response.statusCode,
            'body': Map<String, dynamic>.from(decoded),
          };
        }
      } catch (_) {
        // Non-JSON error pages (proxy/edge) — surface plain text when present.
      }
      final trimmed = body.trim();
      return {
        'status': response.statusCode,
        'body': <String, dynamic>{
          'error': trimmed.isEmpty
              ? 'Сервер вернул ошибку ${response.statusCode}.'
              : (trimmed.length > 240 ? '${trimmed.substring(0, 240)}…' : trimmed),
        },
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<AppStartResult> startWithContact(String contact) async {
    final brand = AppBrand.current;
    final result = await _postJson(
      brand.appStart(),
      {'contact': contact.trim()},
    );
    final status = result['status'] as int;
    final decoded = result['body'] as Map<String, dynamic>;
    if (status != 200) {
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
      url: rawUrl.isEmpty ? null : brandSubscriptionUri(rawUrl),
      publicId: decoded['public_id']?.toString() ?? '',
      expiresAt: int.tryParse('${decoded['expires_at']}') ?? 0,
      active: decoded['active'] != false,
      channel: decoded['channel']?.toString(),
    );
  }

  Future<AppLoginResult> loginWithContact(String contact) async {
    final result = await _postJson(
      AppBrand.current.appLogin(),
      {'contact': contact.trim()},
    );
    final status = result['status'] as int;
    final decoded = result['body'] as Map<String, dynamic>;
    if (status != 200) {
      return AppLoginResult(
        session: '',
        channel: '',
        publicId: '',
        error: decoded['error']?.toString() ?? 'Не получилось начать вход.',
      );
    }
    return AppLoginResult(
      session: decoded['session']?.toString() ?? '',
      channel: decoded['channel']?.toString() ?? '',
      publicId: decoded['public_id']?.toString() ?? '',
      botUrl: decoded['bot_url']?.toString(),
      hint: decoded['hint']?.toString(),
      error: decoded['error']?.toString(),
    );
  }

  Future<List<ConnectedDeviceInfo>> fetchDevices(String token) async {
    final client = HttpClient();
    try {
      final uri = AppBrand.current
          .appDevices()
          .replace(queryParameters: {'token': token});
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw const HttpException('devices');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const HttpException('devices');
      final raw = decoded['devices'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => ConnectedDeviceInfo(
              id: '${item['id'] ?? ''}',
              label: '${item['label'] ?? ''}',
              detail: '${item['detail'] ?? ''}',
              online: item['online'] == true,
            ),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> kickDevice(String token, String deviceId) async {
    final result = await _postJson(
      AppBrand.current.appDevicesKick(),
      {'token': token, 'device_id': deviceId},
    );
    final status = result['status'] as int;
    final decoded = result['body'] as Map<String, dynamic>;
    return status == 200 && decoded['ok'] == true;
  }

  Future<AppLoginStatus> pollLoginStatus(String session) async {
    final client = HttpClient();
    try {
      final uri = AppBrand.current
          .appLoginStatus()
          .replace(queryParameters: {'session': session});
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const HttpException('login-status');
      final rawUrl = decoded['url']?.toString() ?? '';
      return AppLoginStatus(
        status: decoded['status']?.toString() ?? 'expired',
        url: rawUrl.isEmpty ? null : brandSubscriptionUri(rawUrl),
        publicId: decoded['public_id']?.toString(),
        expiresAt: int.tryParse('${decoded['expires_at']}'),
        active: decoded['active'] != false,
        error: decoded['error']?.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ConnectedDeviceInfo {
  const ConnectedDeviceInfo({
    required this.id,
    required this.label,
    required this.detail,
    required this.online,
  });

  final String id;
  final String label;
  final String detail;
  final bool online;
}
