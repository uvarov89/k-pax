part of 'subscription_link.dart';

/// Clash YAML, sing-box JSON and Xray JSON subscriptions.
/// Returns null when the text is none of them.
List<TunnelNode>? _parseConfigFile(String text) {
  final start = text.trimLeft();
  if (start.startsWith('{') || start.startsWith('[')) {
    final Object? decoded;
    try {
      decoded = jsonDecode(start);
    } catch (_) {
      return null;
    }
    return _jsonNodes(_plain(decoded));
  }
  if (RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(text)) {
    final Object? doc;
    try {
      doc = _plain(loadYaml(text));
    } catch (_) {
      return null;
    }
    final proxies = doc is Map ? doc['proxies'] : null;
    if (proxies is! List) return const [];
    return _unique([
      for (final item in proxies)
        if (item is Map<String, Object?>) _safe(() => _clashProxy(item)),
    ]);
  }
  return null;
}

Object? _plain(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): _plain(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _plain(item)];
  return value;
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const [];

String _str(Object? value) => value == null ? '' : value.toString();

int? _int(Object? value) => value is int ? value : int.tryParse(_str(value));

TunnelNode? _safe(TunnelNode? Function() build) {
  try {
    final node = build();
    return node != null && _complete(node) ? node : null;
  } catch (_) {
    return null;
  }
}

/// Xray configs with balancers repeat the same server in every country entry.
List<TunnelNode> _unique(List<TunnelNode?> nodes) {
  final seen = <String>{};
  return [
    for (final node in nodes)
      if (node != null && seen.add(jsonEncode(node.outbound))) node,
  ];
}

TunnelNode _node(String title, TunnelKind kind, String host, int port, Map<String, Object?> outbound) {
  final country = _country(title.isEmpty ? host : title);
  return TunnelNode(
    countryId: country.$1,
    countryCode: country.$2,
    countryName: country.$3,
    kind: kind,
    host: host,
    port: port,
    outbound: outbound,
  );
}

List<TunnelNode> _jsonNodes(Object? decoded) {
  final configs = decoded is List ? decoded : [decoded];
  final nodes = <TunnelNode?>[];
  for (final config in configs) {
    if (config is! Map<String, Object?>) continue;
    final remarks = _str(config['remarks']);
    final outbounds = config['outbounds'];
    final list = outbounds is List
        ? outbounds
        : (config.containsKey('type') || config.containsKey('protocol') ? [config] : const []);
    for (final out in list) {
      if (out is! Map<String, Object?>) continue;
      nodes.add(_safe(() => out.containsKey('protocol') ? _xrayOutbound(out, remarks) : _singboxOutbound(out)));
    }
  }
  return _unique(nodes);
}

const _singboxTypes = {'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'tuic'};

TunnelNode? _singboxOutbound(Map<String, Object?> out) {
  final type = _str(out['type']);
  if (!_singboxTypes.contains(type)) return null;
  final host = _str(out['server']);
  final port = _int(out['server_port']) ?? 443;
  final outbound = Map<String, Object?>.from(out)
    ..remove('detour')
    ..remove('domain_resolver')
    ..remove('domain_strategy');
  outbound['tag'] = 'proxy';
  outbound['server_port'] = port;
  final kind = switch (type) {
    'hysteria2' => TunnelKind.hy2,
    'tuic' => TunnelKind.tuic,
    _ => _kindFor(_str(_map(out['transport'])['type']), ''),
  };
  return _node(_str(out['tag']), kind, host, port, outbound);
}

TunnelNode? _xrayOutbound(Map<String, Object?> out, String remarks) {
  final protocol = _str(out['protocol']);
  final settings = _map(out['settings']);
  final stream = _map(out['streamSettings']);
  final outbound = <String, Object?>{'type': protocol, 'tag': 'proxy'};
  String host;
  int port;
  var flow = '';
  switch (protocol) {
    case 'vless':
    case 'vmess':
      final vnext = _list(settings['vnext']);
      if (vnext.isEmpty) return null;
      final server = _map(vnext.first);
      final users = _list(server['users']);
      final user = _map(users.isEmpty ? null : users.first);
      host = _str(server['address']);
      port = _int(server['port']) ?? 443;
      outbound['uuid'] = _str(user['id']);
      if (protocol == 'vless') {
        flow = _str(user['flow']);
      } else {
        outbound['security'] = _str(user['security']).isEmpty ? 'auto' : _str(user['security']);
        outbound['alter_id'] = _int(user['alterId']) ?? 0;
      }
    case 'trojan':
    case 'shadowsocks':
      final servers = _list(settings['servers']);
      if (servers.isEmpty) return null;
      final server = _map(servers.first);
      host = _str(server['address']);
      port = _int(server['port']) ?? 443;
      outbound['password'] = _str(server['password']);
      if (protocol == 'shadowsocks') outbound['method'] = _str(server['method']);
    default:
      return null;
  }
  outbound['server'] = host;
  outbound['server_port'] = port;

  final network = (_str(stream['network']).isEmpty ? 'tcp' : _str(stream['network'])).toLowerCase();
  final security = (_str(stream['security']).isEmpty ? 'none' : _str(stream['security'])).toLowerCase();
  final query = <String, String>{'security': security};
  switch (network) {
    case 'ws':
      final ws = _map(stream['wsSettings']);
      query['path'] = _str(ws['path']);
      query['host'] = _str(ws['host']).isNotEmpty ? _str(ws['host']) : _str(_map(ws['headers'])['Host']);
    case 'httpupgrade':
      final upgrade = _map(stream['httpupgradeSettings']);
      query['path'] = _str(upgrade['path']);
      query['host'] = _str(upgrade['host']);
    case 'grpc':
      query['serviceName'] = _str(_map(stream['grpcSettings'])['serviceName']);
    case 'tcp':
    case 'raw':
      final tcp = _map(stream['tcpSettings'] ?? stream['rawSettings']);
      query['headerType'] = _str(_map(tcp['header'])['type']).isEmpty ? 'none' : _str(_map(tcp['header'])['type']);
  }
  query.removeWhere((_, value) => value.isEmpty);
  if (protocol == 'shadowsocks') {
    if (network != 'tcp' && network != 'raw') throw UnsupportedLink('ss over $network');
  } else {
    final transport = _transport(network, query);
    if (transport != null) {
      outbound['transport'] = transport;
    } else if (flow.isNotEmpty) {
      outbound['flow'] = flow;
    }
  }
  if (security == 'tls' || security == 'reality') {
    final tls = _map(stream[security == 'tls' ? 'tlsSettings' : 'realitySettings']);
    final alpn = _list(tls['alpn']).map(_str).join(',');
    query.addAll({
      if (_str(tls['serverName']).isNotEmpty) 'sni': _str(tls['serverName']),
      if (_str(tls['fingerprint']).isNotEmpty) 'fp': _str(tls['fingerprint']),
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (tls['allowInsecure'] == true || _str(tls['pinnedPeerCertSha256']).isNotEmpty) 'insecure': '1',
      'pbk': _str(tls['publicKey']),
      'sid': _str(tls['shortId']),
    });
    outbound['tls'] = _tls(query, host, alpnDefault: network == 'grpc' ? 'h2' : null);
  } else if (protocol == 'vless' || protocol == 'trojan') {
    outbound['tls'] = {'enabled': false};
  }
  final title = remarks.isNotEmpty ? remarks : _str(out['tag']);
  return _node(title, _kindFor(network, security), host, port, outbound);
}

TunnelNode? _clashProxy(Map<String, Object?> p) {
  String s(String key) => _str(p[key]);
  final type = s('type').toLowerCase();
  final host = s('server');
  final port = _int(p['port']) ?? 443;
  final reality = _map(p['reality-opts']);
  final tlsOn = p['tls'] == true || type == 'trojan' || reality.isNotEmpty;
  final alpn = _list(p['alpn']).map(_str).join(',');
  final sni = s('servername').isNotEmpty ? s('servername') : s('sni');
  final insecure = p['skip-cert-verify'] == true;
  final query = <String, String>{
    'security': reality.isNotEmpty ? 'reality' : (tlsOn ? 'tls' : 'none'),
    if (sni.isNotEmpty) 'sni': sni,
    if (s('client-fingerprint').isNotEmpty) 'fp': s('client-fingerprint'),
    if (alpn.isNotEmpty) 'alpn': alpn,
    if (insecure) 'insecure': '1',
    'pbk': _str(reality['public-key']),
    'sid': _str(reality['short-id']),
  };
  final outbound = <String, Object?>{'tag': 'proxy', 'server': host, 'server_port': port};

  Map<String, Object?> udpTls() => {
        'enabled': true,
        'server_name': sni.isEmpty ? host : sni,
        if (insecure || s('fingerprint').isNotEmpty) 'insecure': true,
        'alpn': alpn.isEmpty ? ['h3'] : alpn.split(','),
      };

  switch (type) {
    case 'hysteria2':
      outbound.addAll({
        'type': 'hysteria2',
        'password': s('password'),
        if (s('obfs') == 'salamander')
          'obfs': {'type': 'salamander', 'password': s('obfs-password')},
        'tls': udpTls(),
      });
      return _node(s('name'), TunnelKind.hy2, host, port, outbound);
    case 'tuic':
      outbound.addAll({
        'type': 'tuic',
        'uuid': s('uuid'),
        'password': s('password'),
        'congestion_control': s('congestion-controller').isEmpty ? 'bbr' : s('congestion-controller'),
        'udp_relay_mode': s('udp-relay-mode').isEmpty ? 'native' : s('udp-relay-mode'),
        'zero_rtt_handshake': p['reduce-rtt'] == true,
        'tls': udpTls(),
      });
      return _node(s('name'), TunnelKind.tuic, host, port, outbound);
    case 'ss':
      outbound.addAll({'type': 'shadowsocks', 'method': s('cipher'), 'password': s('password')});
      final plugin = s('plugin');
      if (plugin.isNotEmpty) {
        if (plugin != 'obfs') throw UnsupportedLink('ss plugin $plugin');
        final opts = _map(p['plugin-opts']);
        outbound['plugin'] = 'obfs-local';
        outbound['plugin_opts'] = [
          'obfs=${_str(opts['mode']).isEmpty ? 'http' : _str(opts['mode'])}',
          if (_str(opts['host']).isNotEmpty) 'obfs-host=${_str(opts['host'])}',
        ].join(';');
      }
      return _node(s('name'), TunnelKind.reality, host, port, outbound);
    case 'vless':
      outbound.addAll({'type': 'vless', 'uuid': s('uuid')});
    case 'vmess':
      outbound.addAll({
        'type': 'vmess',
        'uuid': s('uuid'),
        'security': s('cipher').isEmpty ? 'auto' : s('cipher'),
        'alter_id': _int(p['alterId']) ?? 0,
      });
    case 'trojan':
      outbound.addAll({'type': 'trojan', 'password': s('password')});
    default:
      return null;
  }

  final network = (s('network').isEmpty ? 'tcp' : s('network')).toLowerCase();
  switch (network) {
    case 'ws':
      final ws = _map(p['ws-opts']);
      query['path'] = _str(ws['path']);
      query['host'] = _str(_map(ws['headers'])['Host']);
      final early = _int(ws['max-early-data']);
      if (early != null && early > 0) query['path'] = '${query['path']}?ed=$early';
    case 'grpc':
      query['serviceName'] = _str(_map(p['grpc-opts'])['grpc-service-name']);
    case 'h2':
      final h2 = _map(p['h2-opts']);
      query['path'] = _str(h2['path']);
      query['host'] = _list(h2['host']).map(_str).join(',');
    case 'http':
      throw const UnsupportedLink('tcp header obfuscation');
  }
  query.removeWhere((_, value) => value.isEmpty);
  final transport = _transport(network, query);
  if (transport != null) {
    outbound['transport'] = transport;
  } else if (type == 'vless' && s('flow').isNotEmpty) {
    outbound['flow'] = s('flow');
  }
  if (tlsOn) {
    outbound['tls'] = _tls(query, host, alpnDefault: network == 'grpc' ? 'h2' : null);
  } else if (type == 'vless') {
    outbound['tls'] = {'enabled': false};
  }
  return _node(s('name'), _kindFor(network, query['security']!), host, port, outbound);
}
