import 'dart:convert';

import 'package:pulse_vpn/core/models/tunnel_node.dart';

class SubscriptionRejected implements Exception {
  const SubscriptionRejected();
}

class AppStartResult {
  const AppStartResult({
    required this.created,
    this.url,
    required this.publicId,
    required this.expiresAt,
    this.active = true,
    this.channel,
    this.error,
  });

  final bool created;
  final Uri? url;
  final String publicId;
  final int expiresAt;
  final bool active;
  final String? channel;
  final String? error;
}

class FetchedSubscription {
  const FetchedSubscription({required this.body, this.userinfo});

  final String body;
  final String? userinfo;
}

Uri? kPaxSubscriptionUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host != 'sub.k-pax.space') {
    return null;
  }
  final token = uri.path.startsWith('/s/') ? uri.path.substring(3) : '';
  if (token.length < 16 || token.contains('/')) return null;
  return uri.replace(query: '', fragment: '');
}

bool looksLikeShare(String raw) {
  final text = raw.trim().toLowerCase();
  return text.contains('vless://') ||
      text.contains('vmess://') ||
      text.contains('trojan://') ||
      text.contains('hy2://') ||
      text.contains('hysteria2://') ||
      RegExp(r'(^|\s)ss://').hasMatch(text);
}

Uri? subscriptionAddress(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri;
}

SubscriptionProfile parseSubscription(String body, {String? userinfo}) {
  final text = _decodeBody(body);
  if (text.contains('Подписка недействительна')) {
    throw const SubscriptionRejected();
  }
  final nodes = <TunnelNode>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.startsWith('vless://')) {
      nodes.add(_vless(trimmed));
    } else if (trimmed.startsWith('hy2://') || trimmed.startsWith('hysteria2://')) {
      nodes.add(_hy2(trimmed));
    } else if (trimmed.startsWith('vmess://')) {
      nodes.add(_vmess(trimmed));
    } else if (trimmed.startsWith('trojan://')) {
      nodes.add(_trojan(trimmed));
    } else if (trimmed.startsWith('ss://')) {
      nodes.add(_shadowsocks(trimmed));
    }
  }
  if (nodes.isEmpty) {
    throw const FormatException('В подписке нет серверов');
  }
  return SubscriptionProfile(nodes: nodes, expiresAt: _expire(userinfo));
}

String _decodeBody(String raw) {
  final trimmed = raw.trim();
  if (trimmed.contains('://')) return trimmed;
  final compact = trimmed.replaceAll(RegExp(r'\s'), '');
  try {
    return utf8.decode(base64.decode(base64.normalize(compact)));
  } catch (_) {
    return trimmed;
  }
}

DateTime? _expire(String? userinfo) {
  if (userinfo == null) return null;
  final match = RegExp(r'expire=(\d+)').firstMatch(userinfo);
  if (match == null) return null;
  final seconds = int.tryParse(match.group(1)!);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
}

TunnelNode _vless(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final title = _title(uri);
  final country = _country(title);
  final transport = (query['type'] ?? 'tcp').toLowerCase();
  final grpc = transport == 'grpc';
  final security = (query['security'] ?? '').toLowerCase();
  final outbound = <String, Object?>{
    'type': 'vless',
    'tag': 'proxy',
    'server': uri.host,
    'server_port': uri.port == 0 ? 443 : uri.port,
    'uuid': uri.userInfo,
  };
  if (!grpc && transport != 'ws' && (query['flow'] ?? '').isNotEmpty) {
    outbound['flow'] = query['flow'];
  }
  final tlsOn = security != 'none';
  final tls = <String, Object?>{
    'enabled': tlsOn,
    if (tlsOn) 'server_name': query['sni'] ?? query['host'] ?? uri.host,
    if (tlsOn)
      'utls': {
        'enabled': true,
        'fingerprint': (query['fp'] ?? 'chrome').isEmpty ? 'chrome' : query['fp'],
      },
  };
  if (grpc) {
    final alpn = query['alpn'];
    tls['alpn'] = (alpn == null || alpn.isEmpty) ? ['h2'] : alpn.split(',');
    outbound['transport'] = {
      'type': 'grpc',
      'service_name': query['serviceName'] ?? 'kpax',
    };
  } else if (transport == 'ws') {
    final hostHeader = query['host'];
    outbound['transport'] = {
      'type': 'ws',
      'path': (query['path'] == null || query['path']!.isEmpty) ? '/' : query['path'],
      if (hostHeader != null && hostHeader.isNotEmpty) 'headers': {'Host': hostHeader},
    };
  } else if (security == 'reality') {
    tls['reality'] = {
      'enabled': true,
      'public_key': query['pbk'] ?? '',
      'short_id': query['sid'] ?? '',
    };
  }
  outbound['tls'] = tls;
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: grpc ? TunnelKind.grpc : TunnelKind.reality,
    host: uri.host,
    port: uri.port == 0 ? 443 : uri.port,
    outbound: outbound,
  );
}

TunnelNode _hy2(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final title = _title(uri);
  final country = _country(title);
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.hy2,
    host: uri.host,
    port: uri.port == 0 ? 443 : uri.port,
    outbound: {
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': uri.host,
      'server_port': uri.port == 0 ? 443 : uri.port,
      'password': Uri.decodeComponent(uri.userInfo),
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        'insecure': query['insecure'] == '1',
      },
    },
  );
}

TunnelNode _vmess(String line) {
  final encoded = line.substring('vmess://'.length).trim();
  final decoded = jsonDecode(utf8.decode(base64.decode(base64.normalize(encoded))));
  if (decoded is! Map) {
    throw const FormatException('vmess');
  }
  final host = decoded['add']?.toString() ?? '';
  final port = int.tryParse('${decoded['port']}') ?? 443;
  final title = decoded['ps']?.toString() ?? host;
  final country = _country(title);
  final network = (decoded['net']?.toString() ?? 'tcp').toLowerCase();
  final tlsOn = (decoded['tls']?.toString() ?? '').isNotEmpty;
  final sni = decoded['sni']?.toString();
  final outbound = <String, Object?>{
    'type': 'vmess',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'uuid': decoded['id']?.toString() ?? '',
    'security': (decoded['scy']?.toString().isNotEmpty ?? false) ? decoded['scy'] : 'auto',
    'alter_id': int.tryParse('${decoded['aid']}') ?? 0,
  };
  if (network == 'ws') {
    final hostHeader = decoded['host']?.toString() ?? '';
    outbound['transport'] = {
      'type': 'ws',
      'path': (decoded['path']?.toString().isEmpty ?? true) ? '/' : decoded['path'],
      if (hostHeader.isNotEmpty) 'headers': {'Host': hostHeader},
    };
  }
  if (tlsOn) {
    outbound['tls'] = {
      'enabled': true,
      'server_name': (sni == null || sni.isEmpty) ? host : sni,
      'utls': {'enabled': true, 'fingerprint': 'chrome'},
    };
  }
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.reality,
    host: host,
    port: port,
    outbound: outbound,
  );
}

TunnelNode _trojan(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final title = _title(uri);
  final country = _country(title);
  final transport = (query['type'] ?? 'tcp').toLowerCase();
  final outbound = <String, Object?>{
    'type': 'trojan',
    'tag': 'proxy',
    'server': uri.host,
    'server_port': uri.port == 0 ? 443 : uri.port,
    'password': Uri.decodeComponent(uri.userInfo),
    'tls': {
      'enabled': (query['security'] ?? 'tls') != 'none',
      'server_name': query['sni'] ?? query['host'] ?? uri.host,
      'utls': {'enabled': true, 'fingerprint': query['fp'] ?? 'chrome'},
    },
  };
  if (transport == 'ws') {
    final hostHeader = query['host'];
    outbound['transport'] = {
      'type': 'ws',
      'path': (query['path'] == null || query['path']!.isEmpty) ? '/' : query['path'],
      if (hostHeader != null && hostHeader.isNotEmpty) 'headers': {'Host': hostHeader},
    };
  }
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.reality,
    host: uri.host,
    port: uri.port == 0 ? 443 : uri.port,
    outbound: outbound,
  );
}

TunnelNode _shadowsocks(String line) {
  var rest = line.substring('ss://'.length);
  final hash = rest.indexOf('#');
  var title = '';
  if (hash >= 0) {
    title = _decodeFragment(rest.substring(hash + 1));
    rest = rest.substring(0, hash);
  }
  late String method;
  late String password;
  late String host;
  late int port;
  if (rest.contains('@')) {
    final uri = Uri.parse('ss://$rest');
    final user = utf8.decode(base64.decode(base64.normalize(uri.userInfo)));
    final split = user.split(':');
    method = split.first;
    password = split.sublist(1).join(':');
    host = uri.host;
    port = uri.port == 0 ? 8388 : uri.port;
    if (title.isEmpty) title = host;
  } else {
    final decoded = utf8.decode(base64.decode(base64.normalize(rest)));
    final uri = Uri.parse('ss://$decoded');
    final user = uri.userInfo.split(':');
    method = user.first;
    password = user.sublist(1).join(':');
    host = uri.host;
    port = uri.port == 0 ? 8388 : uri.port;
    if (title.isEmpty) title = host;
  }
  final country = _country(title);
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.reality,
    host: host,
    port: port,
    outbound: {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
    },
  );
}

String _decodeFragment(String fragment) {
  try {
    return Uri.decodeComponent(fragment);
  } catch (_) {
    return fragment;
  }
}

String _title(Uri uri) {
  final fragment = uri.fragment;
  if (fragment.isEmpty) return uri.host;
  try {
    return Uri.decodeComponent(fragment);
  } catch (_) {
    return fragment;
  }
}

(String, String, String) _country(String title) {
  final low = title.toLowerCase();
  final name = title
      .replaceAll(RegExp(r'\s+запасной$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+hy2$', caseSensitive: false), '')
      .trim();
  if (low.contains('герман')) return ('de', 'DE', name.isEmpty ? 'Германия' : name);
  if (low.contains('финлянд')) return ('fi', 'FI', name.isEmpty ? 'Финляндия' : name);
  if (low.contains('болгар')) return ('bg', 'BG', name.isEmpty ? 'Болгария' : name);
  final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return (id.isEmpty ? 'node' : id, 'NODE', name);
}
