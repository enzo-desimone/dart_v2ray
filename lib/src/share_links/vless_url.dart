import 'v2ray_url.dart';

/// Parser for `vless://` share links.
class VlessUrl extends V2rayUrl {
  VlessUrl({required super.url}) {
    if (!url.startsWith('vless://')) {
      throw ArgumentError('url is invalid');
    }

    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      throw ArgumentError('url is invalid');
    }
    uri = parsedUri;

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
      fingerprint:
          uri.queryParameters['fp'] ??
          streamSetting['tlsSettings']?['fingerprint'],
      alpns: uri.queryParameters['alpn'],
      publicKey: uri.queryParameters['pbk'] ?? '',
      shortId: uri.queryParameters['sid'] ?? '',
      spiderX: uri.queryParameters['spx'] ?? '',
    );
  }

  /// Parsed URI for this share link.
  late final Uri uri;

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': <String, dynamic>{
      'vnext': <Map<String, dynamic>>[
        <String, dynamic>{
          'address': address,
          'port': port,
          'users': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': uri.userInfo,
              'level': level,
              'encryption': uri.queryParameters['encryption'] ?? 'none',
              'flow':
                  (uri.queryParameters['flow']?.isEmpty ?? true)
                      ? null
                      : uri.queryParameters['flow'],
            },
          ],
        },
      ],
      'servers': null,
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
