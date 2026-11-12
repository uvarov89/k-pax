import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/core/models/tunnel_node.dart';

part 'subscription_formats.dart';

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

class AppLoginResult {
  const AppLoginResult({
    required this.session,
    required this.channel,
    required this.publicId,
    this.botUrl,
    this.hint,
    this.error,
    this.needsEmailLink = false,
  });

  final String session;
  final String channel;
  final String publicId;
  final String? botUrl;
  final String? hint;
  final String? error;
  final bool needsEmailLink;

  bool get isTelegram => channel == 'telegram';
  bool get isEmail => channel == 'email';
}

class AppLoginStatus {
  const AppLoginStatus({
    required this.status,
    this.url,
    this.publicId,
    this.expiresAt,
    this.active = true,
    this.error,
    this.needsEmailLink = false,
  });

  final String status;
  final Uri? url;
  final String? publicId;
  final int? expiresAt;
  final bool active;
  final String? error;
  final bool needsEmailLink;

  bool get isPending => status == 'pending';
  bool get isReady => status == 'ready' && url != null;
  bool get isExpired => status == 'expired';
}

class FetchedSubscription {
  const FetchedSubscription({
    required this.body,
    this.userinfo,
    this.publicId,
    this.title,
    this.webPage,
    this.needsEmailLink = false,
  });

  final String body;
  final String? userinfo;
  final String? publicId;
  final String? title;
  final Uri? webPage;
  final bool needsEmailLink;
}

/// `profile-title` is plain text or `base64:...`.
String? profileTitle(String? header) {
  var value = (header ?? '').trim();
  if (value.isEmpty) return null;
  if (value.toLowerCase().startsWith('base64:')) {
    try {
      value = utf8.decode(base64.decode(base64.normalize(value.substring(7).trim())));
    } catch (_) {
      return null;
    }
  }
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return null;
  return value.length > 40 ? value.substring(0, 40) : value;
}

Uri? providerPage(String? header) {
  final uri = Uri.tryParse((header ?? '').trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
}

/// A share link the tunnel core cannot run (for example XHTTP or mKCP).
class UnsupportedLink implements Exception {
  const UnsupportedLink(this.reason);

  final String reason;
}

Uri? brandSubscriptionUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  final host = AppBrand.current.subHost;
  if (uri == null || uri.scheme != 'https' || uri.host != host) {
    return null;
  }
  final token = uri.path.startsWith('/s/') ? uri.path.substring(3) : '';
  if (token.length < 16 || token.contains('/')) return null;
  return uri.replace(query: '', fragment: '');
}

/// Legacy alias — owned-brand subscription URL for the active flavor.
Uri? kPaxSubscriptionUri(String raw) => brandSubscriptionUri(raw);

bool looksLikeShare(String raw) {
  final text = raw.trim().toLowerCase();
  return text.contains('vless://') ||
      text.contains('vmess://') ||
      text.contains('trojan://') ||
      text.contains('hy2://') ||
      text.contains('hysteria2://') ||
      text.contains('tuic://') ||
      RegExp(r'(^|\s)ss://').hasMatch(text);
}

Uri? subscriptionAddress(String raw) {
  final text = raw.trim();
  // Plain emails / telegram nicks must not be treated as http(s) URLs.
  if (text.contains('@') && !text.contains('://')) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri;
}

/// Normalize profile input before /app/login (email, @nick, t.me links).
String normalizeContactInput(String raw) {
  var text = raw.replaceAll('\u200b', '').replaceAll('\u00a0', ' ').trim();
  text = text.replaceAll('＠', '@');
  if (text.toLowerCase().startsWith('mailto:')) {
    text = text.substring(7).trim();
  }
  final angled = RegExp(r'<([^>]+@[^>]+)>').firstMatch(text);
  if (angled != null) {
    text = angled.group(1)!.trim();
  }
  return text;
}

SubscriptionProfile parseSubscription(String body, {String? userinfo}) {
  final text = _decodeBody(body);
  if (text.contains('Подписка недействительна')) {
    throw const SubscriptionRejected();
  }
  final configured = _parseConfigFile(text);
  if (configured != null) {
    if (configured.isEmpty) {
      throw const FormatException('В подписке нет серверов, которые поддерживает приложение');
    }
    return SubscriptionProfile(nodes: configured, expiresAt: _expire(userinfo));
  }
  final nodes = <TunnelNode>[];
  var skipped = 0;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final node = _parseLine(trimmed);
    if (node == null) {
      if (trimmed.contains('://')) skipped++;
      continue;
    }
    nodes.add(node);
  }
  if (nodes.isEmpty) {
    throw FormatException(
      skipped > 0 ? 'В подписке нет серверов, которые поддерживает приложение' : 'В подписке нет серверов',
    );
  }
  return SubscriptionProfile(nodes: nodes, expiresAt: _expire(userinfo));
}

/// One broken or unsupported line must not hide the rest of the subscription.
TunnelNode? _parseLine(String line) {
  try {
    final lower = line.toLowerCase();
    TunnelNode? node;
    if (lower.startsWith('vless://')) {
      node = _vless(line);
    } else if (lower.startsWith('hy2://') || lower.startsWith('hysteria2://')) {
      node = _hy2(line);
    } else if (lower.startsWith('tuic://')) {
      node = _tuic(line);
    } else if (lower.startsWith('vmess://')) {
      node = _vmess(line);
    } else if (lower.startsWith('trojan://')) {
      node = _trojan(line);
    } else if (lower.startsWith('ss://')) {
      node = _shadowsocks(line);
    }
    return node != null && _complete(node) ? node : null;
  } catch (_) {
    return null;
  }
}

bool _complete(TunnelNode node) {
  if (node.host.isEmpty || node.port <= 0 || node.port > 65535) return false;
  final out = node.outbound;
  final secret = (out['uuid'] ?? out['password'] ?? '').toString();
  return secret.isNotEmpty;
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

bool _truthy(String? value) {
  final v = (value ?? '').toLowerCase();
  return v == '1' || v == 'true' || v == 'yes';
}

List<String>? _alpn(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
}

/// sing-box transport for v2ray-style links. Returns null for plain TCP.
Map<String, Object?>? _transport(String type, Map<String, String> q) {
  switch (type) {
    case '':
    case 'tcp':
    case 'raw':
      if ((q['headerType'] ?? 'none') != 'none') {
        throw const UnsupportedLink('tcp header obfuscation');
      }
      return null;
    case 'ws':
      final host = q['host'] ?? '';
      var path = (q['path'] == null || q['path']!.isEmpty) ? '/' : q['path']!;
      final transport = <String, Object?>{'type': 'ws'};
      final early = RegExp(r'[?&]ed=(\d+)').firstMatch(path);
      if (early != null) {
        path = path.replaceFirst(RegExp(r'[?&]ed=\d+'), '');
        transport['max_early_data'] = int.parse(early.group(1)!);
        transport['early_data_header_name'] = 'Sec-WebSocket-Protocol';
      }
      transport['path'] = path.isEmpty ? '/' : path;
      if (host.isNotEmpty) transport['headers'] = {'Host': host};
      return transport;
    case 'grpc':
      return {
        'type': 'grpc',
        'service_name': q['serviceName'] ?? q['servicename'] ?? '',
      };
    case 'httpupgrade':
      final host = q['host'] ?? '';
      return {
        'type': 'httpupgrade',
        'path': (q['path'] == null || q['path']!.isEmpty) ? '/' : q['path'],
        if (host.isNotEmpty) 'host': host,
      };
    case 'h2':
    case 'http':
      final host = q['host'] ?? '';
      return {
        'type': 'http',
        'path': (q['path'] == null || q['path']!.isEmpty) ? '/' : q['path'],
        if (host.isNotEmpty) 'host': host.split(',').map((item) => item.trim()).toList(),
      };
    default:
      throw UnsupportedLink(type);
  }
}

TunnelKind _kindFor(String transport, String security) {
  if (transport == 'grpc' || transport == 'h2' || transport == 'http') return TunnelKind.grpc;
  if (transport == 'ws' || transport == 'httpupgrade') return TunnelKind.message;
  return TunnelKind.reality;
}

Map<String, Object?> _tls(Map<String, String> q, String fallbackHost, {String? alpnDefault}) {
  final security = (q['security'] ?? 'tls').toLowerCase();
  if (security == 'none' || security.isEmpty) return {'enabled': false};
  final fp = (q['fp'] ?? '').isEmpty ? 'chrome' : q['fp']!;
  final alpn = _alpn(q['alpn']) ?? (alpnDefault == null ? null : [alpnDefault]);
  final tls = <String, Object?>{
    'enabled': true,
    'server_name': q['sni'] ?? q['peer'] ?? q['host'] ?? fallbackHost,
    'utls': {'enabled': true, 'fingerprint': fp},
    if (_truthy(q['allowInsecure']) || _truthy(q['insecure'])) 'insecure': true,
    if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
  };
  if (security == 'reality') {
    tls['reality'] = {
      'enabled': true,
      'public_key': q['pbk'] ?? '',
      'short_id': q['sid'] ?? '',
    };
  }
  return tls;
}

TunnelNode _vless(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final country = _country(_title(uri));
  final transport = (query['type'] ?? 'tcp').toLowerCase();
  final security = (query['security'] ?? 'none').toLowerCase();
  final kind = _kindFor(transport, security);
  final port = uri.port == 0 ? 443 : uri.port;
  final outbound = <String, Object?>{
    'type': 'vless',
    'tag': 'proxy',
    'server': uri.host,
    'server_port': port,
    'uuid': Uri.decodeComponent(uri.userInfo),
  };
  final stream = _transport(transport, query);
  if (stream == null && (query['flow'] ?? '').isNotEmpty) {
    outbound['flow'] = query['flow'];
  }
  if (stream != null) outbound['transport'] = stream;
  outbound['tls'] = security == 'none'
      ? {'enabled': false}
      : _tls(query, uri.host, alpnDefault: transport == 'grpc' ? 'h2' : null);
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: kind,
    host: uri.host,
    port: port,
    outbound: outbound,
  );
}

TunnelNode _hy2(String line) {
  final uri = Uri.parse(line.replaceFirst(RegExp(r'^hysteria2://', caseSensitive: false), 'hy2://'));
  final query = uri.queryParameters;
  final country = _country(_title(uri));
  final port = uri.port == 0 ? 443 : uri.port;
  final obfs = (query['obfs'] ?? '').toLowerCase();
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.hy2,
    host: uri.host,
    port: port,
    outbound: {
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': uri.host,
      'server_port': port,
      'password': Uri.decodeComponent(uri.userInfo),
      if (obfs == 'salamander')
        'obfs': {'type': 'salamander', 'password': query['obfs-password'] ?? ''},
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        // sing-box cannot pin a certificate hash; a pinned self-signed server is accepted as insecure.
        'insecure': _truthy(query['insecure']) || (query['pinSHA256'] ?? '').isNotEmpty,
        'alpn': ['h3'],
      },
    },
  );
}

TunnelNode _tuic(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final country = _country(_title(uri));
  final user = Uri.decodeComponent(uri.userInfo);
  final split = user.split(':');
  final alpn = _alpn(query['alpn']);
  final port = uri.port == 0 ? 2087 : uri.port;
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: TunnelKind.tuic,
    host: uri.host,
    port: port,
    outbound: {
      'type': 'tuic',
      'tag': 'proxy',
      'server': uri.host,
      'server_port': port,
      'uuid': split.first,
      'password': split.length > 1 ? split.sublist(1).join(':') : (query['password'] ?? ''),
      'congestion_control': query['congestion_control'] ?? 'bbr',
      'udp_relay_mode': query['udp_relay_mode'] ?? 'native',
      'zero_rtt_handshake': _truthy(query['zero_rtt_handshake']),
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        if (_truthy(query['allow_insecure']) || _truthy(query['insecure'])) 'insecure': true,
        'alpn': (alpn == null || alpn.isEmpty) ? ['h3'] : alpn,
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
  String field(String key) => decoded[key]?.toString() ?? '';
  final host = field('add');
  final port = int.tryParse(field('port')) ?? 443;
  final title = field('ps').isEmpty ? host : field('ps');
  final country = _country(title);
  final network = (field('net').isEmpty ? 'tcp' : field('net')).toLowerCase();
  final tlsOn = field('tls').isNotEmpty && field('tls') != 'none';
  final query = <String, String>{
    'host': field('host'),
    'path': field('path'),
    'serviceName': field('path'),
    'headerType': field('type').isEmpty ? 'none' : field('type'),
    'sni': field('sni').isEmpty ? (field('host').isEmpty ? host : field('host')) : field('sni'),
    'alpn': field('alpn'),
    'fp': field('fp'),
    'security': tlsOn ? 'tls' : 'none',
    if (_truthy(field('allowInsecure')) || _truthy(field('insecure'))) 'insecure': '1',
  };
  final outbound = <String, Object?>{
    'type': 'vmess',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'uuid': field('id'),
    'security': field('scy').isNotEmpty ? field('scy') : 'auto',
    'alter_id': int.tryParse(field('aid')) ?? 0,
  };
  final stream = _transport(network, query);
  if (stream != null) outbound['transport'] = stream;
  if (tlsOn) outbound['tls'] = _tls(query, host, alpnDefault: network == 'grpc' ? 'h2' : null);
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: _kindFor(network, tlsOn ? 'tls' : 'none'),
    host: host,
    port: port,
    outbound: outbound,
  );
}

TunnelNode _trojan(String line) {
  final uri = Uri.parse(line);
  final query = uri.queryParameters;
  final country = _country(_title(uri));
  final transport = (query['type'] ?? 'tcp').toLowerCase();
  final port = uri.port == 0 ? 443 : uri.port;
  final outbound = <String, Object?>{
    'type': 'trojan',
    'tag': 'proxy',
    'server': uri.host,
    'server_port': port,
    'password': Uri.decodeComponent(uri.userInfo),
    'tls': _tls(query, uri.host, alpnDefault: transport == 'grpc' ? 'h2' : null),
  };
  final stream = _transport(transport, query);
  if (stream != null) outbound['transport'] = stream;
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: _kindFor(transport, query['security'] ?? 'tls'),
    host: uri.host,
    port: port,
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
  var plugin = '';
  if (rest.contains('@')) {
    final uri = Uri.parse('ss://$rest');
    final info = Uri.decodeComponent(uri.userInfo);
    // SIP002: base64(method:password) or plain method:password (Shadowsocks 2022).
    String user;
    if (info.contains(':')) {
      user = info;
    } else {
      user = utf8.decode(base64.decode(base64.normalize(info)));
    }
    final split = user.split(':');
    method = split.first;
    password = split.sublist(1).join(':');
    host = uri.host;
    port = uri.port == 0 ? 8388 : uri.port;
    plugin = uri.queryParameters['plugin'] ?? '';
    if (title.isEmpty) title = host;
  } else {
    final query = rest.indexOf('?');
    final payload = query >= 0 ? rest.substring(0, query) : rest;
    final decoded = utf8.decode(base64.decode(base64.normalize(payload)));
    final uri = Uri.parse('ss://$decoded');
    final user = uri.userInfo.split(':');
    method = user.first;
    password = user.sublist(1).join(':');
    host = uri.host;
    port = uri.port == 0 ? 8388 : uri.port;
    if (title.isEmpty) title = host;
  }
  final outbound = <String, Object?>{
    'type': 'shadowsocks',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'method': method,
    'password': password,
  };
  if (plugin.isNotEmpty) {
    final parts = plugin.split(';');
    final name = parts.first;
    if (name != 'obfs-local' && name != 'simple-obfs' && name != 'v2ray-plugin') {
      throw UnsupportedLink('ss plugin $name');
    }
    outbound['plugin'] = name == 'simple-obfs' ? 'obfs-local' : name;
    outbound['plugin_opts'] = parts.skip(1).join(';');
  }
  final country = _country(title);
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

/// ISO code → Russian name and words that identify the country in server titles.
const Map<String, (String, List<String>)> _countries = {
  'DE': ('Германия', ['герман', 'germany', 'deutschland', 'frankfurt', 'франкфурт', 'berlin', 'берлин']),
  'FI': ('Финляндия', ['финлянд', 'finland', 'helsinki', 'хельсинки']),
  'BG': ('Болгария', ['болгар', 'bulgaria', 'sofia', 'софия']),
  'NL': ('Нидерланды', ['нидерланд', 'голланд', 'netherlands', 'holland', 'amsterdam', 'амстердам']),
  'SE': ('Швеция', ['швец', 'sweden', 'stockholm', 'стокгольм']),
  'NO': ('Норвегия', ['норвег', 'norway', 'oslo']),
  'DK': ('Дания', ['дания', 'denmark', 'copenhagen']),
  'PL': ('Польша', ['польш', 'poland', 'warsaw', 'варшав']),
  'CZ': ('Чехия', ['чехия', 'чехии', 'czech', 'prague', 'прага', 'праге']),
  'AT': ('Австрия', ['австри', 'austria', 'vienna', 'вена']),
  'CH': ('Швейцария', ['швейцар', 'switzerland', 'zurich', 'цюрих']),
  'FR': ('Франция', ['франци', 'france', 'paris', 'париж']),
  'GB': ('Великобритания', ['великобритан', 'британ', 'англи', 'united kingdom', 'britain', 'england', 'london', 'лондон']),
  'IE': ('Ирландия', ['ирланд', 'ireland', 'dublin']),
  'ES': ('Испания', ['испани', 'spain', 'madrid', 'мадрид']),
  'PT': ('Португалия', ['португал', 'portugal', 'lisbon']),
  'IT': ('Италия', ['итали', 'italy', 'milan', 'милан', 'rome']),
  'BE': ('Бельгия', ['бельги', 'belgium', 'brussels']),
  'LU': ('Люксембург', ['люксембург', 'luxembourg']),
  'LV': ('Латвия', ['латви', 'latvia', 'riga', 'рига']),
  'LT': ('Литва', ['литва', 'литве', 'lithuania', 'vilnius']),
  'EE': ('Эстония', ['эстони', 'estonia', 'tallinn', 'таллин']),
  'RO': ('Румыния', ['румын', 'romania', 'bucharest']),
  'HU': ('Венгрия', ['венгр', 'hungary', 'budapest']),
  'RS': ('Сербия', ['серби', 'serbia', 'belgrade']),
  'MD': ('Молдова', ['молдов', 'moldova', 'chisinau']),
  'GR': ('Греция', ['греци', 'greece', 'athens']),
  'CY': ('Кипр', ['кипр', 'кипре', 'cyprus']),
  'HR': ('Хорватия', ['хорват', 'croatia']),
  'SK': ('Словакия', ['словаки', 'slovakia']),
  'SI': ('Словения', ['словени', 'slovenia']),
  'IS': ('Исландия', ['исланд', 'iceland']),
  'TR': ('Турция', ['турци', 'turkey', 'türkiye', 'istanbul', 'стамбул']),
  'GE': ('Грузия', ['грузи', 'georgia', 'tbilisi']),
  'AM': ('Армения', ['армени', 'armenia', 'yerevan']),
  'KZ': ('Казахстан', ['казахстан', 'kazakhstan', 'almaty', 'алматы']),
  'UZ': ('Узбекистан', ['узбекистан', 'uzbekistan', 'tashkent']),
  'KG': ('Киргизия', ['киргиз', 'кыргыз', 'kyrgyz', 'bishkek']),
  'UA': ('Украина', ['украин', 'ukraine', 'kyiv', 'kiev']),
  'BY': ('Беларусь', ['беларус', 'белорусс', 'belarus', 'minsk', 'минск']),
  'RU': ('Россия', ['россия', 'россии', 'russia', 'moscow', 'москв']),
  'US': ('США', ['сша', 'америк', 'united states', 'usa', 'america', 'new york', 'los angeles']),
  'CA': ('Канада', ['канад', 'canada', 'toronto']),
  'MX': ('Мексика', ['мексик', 'mexico']),
  'BR': ('Бразилия', ['бразил', 'brazil']),
  'AR': ('Аргентина', ['аргентин', 'argentina']),
  'JP': ('Япония', ['япони', 'japan', 'tokyo', 'токио']),
  'KR': ('Корея', ['корея', 'korea', 'seoul']),
  'SG': ('Сингапур', ['сингапур', 'singapore']),
  'HK': ('Гонконг', ['гонконг', 'hong kong', 'hongkong']),
  'TW': ('Тайвань', ['тайван', 'taiwan']),
  'IN': ('Индия', ['индия', 'индии', 'india', 'mumbai']),
  'AE': ('ОАЭ', ['оаэ', 'эмират', 'emirates', 'uae', 'dubai', 'дубай']),
  'IL': ('Израиль', ['израил', 'israel']),
  'TH': ('Таиланд', ['таиланд', 'thailand', 'bangkok']),
  'VN': ('Вьетнам', ['вьетнам', 'vietnam']),
  'ID': ('Индонезия', ['индонези', 'indonesia', 'jakarta']),
  'MY': ('Малайзия', ['малайзи', 'malaysia']),
  'AU': ('Австралия', ['австрали', 'australia', 'sydney']),
  'ZA': ('ЮАР', ['юар', 'south africa']),
};

String? _flagCode(String title) {
  final runes = title.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i];
    final b = runes[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      final code = String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
      return code == 'UK' ? 'GB' : code;
    }
  }
  return null;
}

String? _codeToken(String title) {
  for (final match in RegExp(r'(?<![A-Za-z])([A-Z]{2})(?![A-Za-z])').allMatches(title)) {
    final code = match.group(1)!;
    if (code == 'UK') return 'GB';
    if (_countries.containsKey(code)) return code;
  }
  return null;
}

String? _nameCode(String low) {
  for (final entry in _countries.entries) {
    for (final word in entry.value.$2) {
      if (_mentions(low, word)) return entry.key;
    }
  }
  return null;
}

/// Short words (usa, uae, сша) must stand alone, longer stems may start a word.
bool _mentions(String low, String word) {
  final escaped = RegExp.escape(word);
  final pattern = word.length <= 4
      ? '(?<![a-zа-яё])$escaped(?![a-zа-яё])'
      : '(?<![a-zа-яё])$escaped';
  return RegExp(pattern, unicode: true).hasMatch(low);
}

String _cleanTitle(String title) {
  return title
      .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
      .replaceAll(
        RegExp(r'\s+(запасной|hy2|tuic|сообщения)$', caseSensitive: false),
        '',
      )
      .trim();
}

(String, String, String) _country(String title) {
  final low = title.toLowerCase();
  final name = _cleanTitle(title);
  final code = _flagCode(title) ?? _nameCode(low) ?? _codeToken(title);
  if (code != null) {
    final known = _countries[code];
    return (code.toLowerCase(), code, known?.$1 ?? (name.isEmpty ? code : name));
  }
  final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '-');
  return (id.isEmpty ? 'node' : id, 'NODE', name.isEmpty ? title : name);
}
