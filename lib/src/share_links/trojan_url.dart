import 'v2ray_url.dart';

/// Parser for `trojan://` share links.
class TrojanUrl extends V2rayUrl {
  TrojanUrl({required super.url}) {
    if (!url.startsWith('trojan://')) {
      throw ArgumentError('url is invalid');
    }

    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      throw ArgumentError('url is invalid');
    }
    uri = parsedUri;

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
        streamSecurity: uri.queryParameters['security'] ?? 'tls',
        allowInsecure: allowInsecure,
        sni: uri.queryParameters['sni'] ?? sni,
        fingerprint:
            streamSetting['tlsSettings']?['fingerprint'] ?? 'randomized',
        alpns: uri.queryParameters['alpn'],
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
      flow = uri.queryParameters['flow'] ?? '';
    } else {
      super.populateTlsSettings(
        streamSecurity: 'tls',
        allowInsecure: allowInsecure,
        sni: '',
        fingerprint:
            streamSetting['tlsSettings']?['fingerprint'] ?? 'randomized',
        alpns: null,
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
    }
  }

  /// Parsed URI for this share link.
  late final Uri uri;

  /// Optional Trojan flow value.
  String flow = '';

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'trojan',
    'settings': <String, dynamic>{
      'vnext': null,
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'address': address,
          'method': 'chacha20-poly1305',
          'ota': false,
          'password': uri.userInfo,
          'port': port,
          'level': level,
          'email': null,
          'flow': flow,
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
