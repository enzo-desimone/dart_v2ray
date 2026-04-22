import 'dart:convert';

import 'v2ray_url.dart';

/// Parser for `ss://` share links.
class ShadowsocksUrl extends V2rayUrl {
  ShadowsocksUrl({required super.url}) {
    if (!url.startsWith('ss://')) {
      throw ArgumentError('url is invalid');
    }

    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      throw ArgumentError('url is invalid');
    }
    uri = parsedUri;

    if (uri.userInfo.isNotEmpty) {
      String raw = uri.userInfo;
      if (raw.length % 4 > 0) {
        raw += '=' * (4 - raw.length % 4);
      }
      try {
        final String methodPass = utf8.decode(base64Decode(raw));
        method = methodPass.split(':')[0];
        password = methodPass.substring(method.length + 1);
      } catch (_) {
        // Keep defaults when credentials cannot be decoded.
      }
    }

    if (uri.queryParameters.isNotEmpty) {
      final String sni = super.populateTransportSettings(
        transport: uri.queryParameters['type'] ?? 'tcp',
        headerType: uri.queryParameters['headerType'],
        host: uri.queryParameters['host'],
        path: uri.queryParameters['path'],
        seed: uri.queryParameters['seed'],
        quicSecurity: uri.queryParameters['quicSecurity'],
        key: uri.queryParameters['key'],
        mode: uri.queryParameters['mode'],
        serviceName: uri.queryParameters['serviceName'],
      );
      super.populateTlsSettings(
        streamSecurity: uri.queryParameters['security'] ?? '',
        allowInsecure: allowInsecure,
        sni: uri.queryParameters['sni'] ?? sni,
        fingerprint: streamSetting['tlsSettings']?['fingerprint'],
        alpns: uri.queryParameters['alpn'],
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
    }
  }

  /// Parsed URI for this share link.
  late final Uri uri;

  /// Cipher method for Shadowsocks.
  String method = 'none';

  /// Password for Shadowsocks.
  String password = '';

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'shadowsocks',
    'settings': <String, dynamic>{
      'vnext': null,
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'address': address,
          'method': method,
          'ota': false,
          'password': password,
          'port': port,
          'level': level,
          'email': null,
          'flow': null,
          'ivCheck': null,
          'users': null,
        },
      ],
      'response': null,
      'network': null,
      'address': null,
      'port': null,
      'domainStrategy': null,
      'redirect': null,
      'userLevel': null,
      'inboundTag': null,
      'secretKey': null,
      'peers': null,
    },
    'streamSettings': streamSetting,
    'proxySettings': null,
    'sendThrough': null,
    'mux': <String, dynamic>{'enabled': false, 'concurrency': 8},
  };
}
