import 'dart:convert';

/// Base parser for supported V2Ray/Xray share links.
///
/// Concrete implementations convert a share link into a full JSON
/// configuration consumable by Xray core.
abstract class V2rayUrl {
  V2rayUrl({required this.url});

  /// Raw share link provided by the caller.
  final String url;

  /// Whether insecure TLS certificate validation is allowed.
  bool get allowInsecure => true;

  /// Default VMess security value.
  String get security => 'auto';

  /// Default user level for outbound accounts.
  int get level => 8;

  /// Default destination port.
  int get port => 443;

  /// Default transport network.
  String get network => 'tcp';

  /// Destination host.
  String get address => '';

  /// Human-readable profile name from the share link.
  String get remark => '';

  /// Protocol-specific outbound definition.
  Map<String, dynamic> get outbound1;

  /// Default inbound socks listener used by generated configurations.
  Map<String, dynamic> inbound = <String, dynamic>{
    'tag': 'in_proxy',
    'port': 10807,
    'protocol': 'socks',
    'listen': '127.0.0.1',
    'settings': <String, dynamic>{
      'auth': 'noauth',
      'udp': true,
      'userLevel': 8,
      'address': null,
      'port': null,
      'network': null,
    },
    'sniffing': <String, dynamic>{
      'enabled': false,
      'destOverride': null,
      'metadataOnly': null,
    },
    'streamSettings': null,
    'allocate': null,
  };

  /// Default log section for generated configurations.
  Map<String, dynamic> log = <String, dynamic>{
    'access': '',
    'error': '',
    'loglevel': 'error',
    'dnsLog': false,
  };

  /// Default direct outbound.
  Map<String, dynamic> outbound2 = <String, dynamic>{
    'tag': 'direct',
    'protocol': 'freedom',
    'settings': <String, dynamic>{
      'vnext': null,
      'servers': null,
      'response': null,
      'network': null,
      'address': null,
      'port': null,
      'domainStrategy': 'UseIp',
      'redirect': null,
      'userLevel': null,
      'inboundTag': null,
      'secretKey': null,
      'peers': null,
    },
    'streamSettings': null,
    'proxySettings': null,
    'sendThrough': null,
    'mux': null,
  };

  /// Default blackhole outbound.
  Map<String, dynamic> outbound3 = <String, dynamic>{
    'tag': 'blackhole',
    'protocol': 'blackhole',
    'settings': <String, dynamic>{
      'vnext': null,
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
    'streamSettings': null,
    'proxySettings': null,
    'sendThrough': null,
    'mux': null,
  };

  /// DNS section used by generated configurations.
  Map<String, dynamic> dns = <String, dynamic>{
    'servers': <String>['8.8.8.8', '8.8.4.4'],
  };

  /// Routing section used by generated configurations.
  Map<String, dynamic> routing = <String, dynamic>{
    'domainStrategy': 'UseIp',
    'domainMatcher': null,
    'rules': <dynamic>[],
    'balancers': <dynamic>[],
  };

  /// Complete generated configuration map.
  Map<String, dynamic> get fullConfiguration => <String, dynamic>{
    'log': log,
    'inbounds': <Map<String, dynamic>>[inbound],
    'outbounds': <Map<String, dynamic>>[outbound1, outbound2, outbound3],
    'dns': dns,
    'routing': routing,
  };

  /// Transport/security section populated by concrete parsers.
  late Map<String, dynamic> streamSetting = <String, dynamic>{
    'network': network,
    'security': '',
    'tcpSettings': null,
    'kcpSettings': null,
    'wsSettings': null,
    'httpSettings': null,
    'tlsSettings': null,
    'quicSettings': null,
    'realitySettings': null,
    'grpcSettings': null,
    'dsSettings': null,
    'sockopt': null,
  };

  /// Encodes [fullConfiguration] into a pretty JSON string.
  ///
  /// [indent] controls the number of spaces used for formatting.
  String getFullConfiguration({int indent = 2}) {
    final dynamic sanitized = removeNulls(
      Map<String, dynamic>.from(fullConfiguration),
    );
    return JsonEncoder.withIndent(' ' * indent).convert(sanitized);
  }

  /// Populates transport-specific settings and returns the derived SNI host.
  String populateTransportSettings({
    required String transport,
    required String? headerType,
    required String? host,
    required String? path,
    required String? seed,
    required String? quicSecurity,
    required String? key,
    required String? mode,
    required String? serviceName,
  }) {
    String sni = '';
    streamSetting['network'] = transport;

    if (transport == 'tcp') {
      streamSetting['tcpSettings'] = <String, dynamic>{
        'header': <String, dynamic>{'type': 'none', 'request': null},
        'acceptProxyProtocol': null,
      };

      if (headerType == 'http') {
        streamSetting['tcpSettings']['header']['type'] = 'http';
        if (host != '' || path != '') {
          streamSetting['tcpSettings']['header']['request'] = <String, dynamic>{
            'path': path == null ? <String>['/'] : path.split(','),
            'headers': <String, dynamic>{
              'Host': host == null ? '' : host.split(','),
              'User-Agent': <String>[
                'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36',
                'Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_2 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/53.0.2785.109 Mobile/14A456 Safari/601.1.46',
              ],
              'Accept-Encoding': <String>['gzip, deflate'],
              'Connection': <String>['keep-alive'],
              'Pragma': <String>['no-cache'],
            },
            'version': '1.1',
            'method': 'GET',
          };
          sni =
              streamSetting['tcpSettings']['header']['request']['headers']['Host']
                          .length >
                      0
                  ? streamSetting['tcpSettings']['header']['request']['headers']['Host'][0]
                  : sni;
        }
      } else {
        streamSetting['tcpSettings']['header']['type'] = 'none';
        sni = host != '' ? host ?? '' : '';
      }
    } else if (transport == 'kcp') {
      streamSetting['kcpSettings'] = <String, dynamic>{
        'mtu': 1350,
        'tti': 50,
        'uplinkCapacity': 12,
        'downlinkCapacity': 100,
        'congestion': false,
        'readBufferSize': 1,
        'writeBufferSize': 1,
        'header': <String, dynamic>{'type': headerType ?? 'none'},
        'seed': (seed == null || seed == '') ? null : seed,
      };
    } else if (transport == 'ws') {
      streamSetting['wsSettings'] = <String, dynamic>{
        'path': path ?? <String>['/'],
        'headers': <String, dynamic>{'Host': host ?? ''},
        'maxEarlyData': null,
        'useBrowserForwarding': null,
        'acceptProxyProtocol': null,
      };
      sni = streamSetting['wsSettings']['headers']['Host'] as String;
    } else if (transport == 'h2' || transport == 'http') {
      streamSetting['network'] = 'h2';
      streamSetting['h2Setting'] = <String, dynamic>{
        'host': host?.split(',') ?? '',
        'path': path ?? <String>['/'],
      };
      sni =
          streamSetting['h2Setting']['host'].length > 0
              ? streamSetting['h2Setting']['host'][0] as String
              : sni;
    } else if (transport == 'quic') {
      streamSetting['quicSettings'] = <String, dynamic>{
        'security': quicSecurity ?? 'none',
        'key': key ?? '',
        'header': <String, dynamic>{'type': headerType ?? 'none'},
      };
    } else if (transport == 'grpc') {
      streamSetting['grpcSettings'] = <String, dynamic>{
        'serviceName': serviceName ?? '',
        'multiMode': mode == 'multi',
      };
      sni = host ?? '';
    } else if (transport == 'xhttp') {
      streamSetting['network'] = 'xhttp';
      streamSetting['xhttpSettings'] = <String, dynamic>{
        'host': host ?? '',
        'mode': mode ?? 'auto',
        'path': path ?? '/',
      };
      sni = host ?? '';
    }
    return sni;
  }

  /// Populates TLS or Reality settings on [streamSetting].
  void populateTlsSettings({
    required String? streamSecurity,
    required bool allowInsecure,
    required String? sni,
    required String? fingerprint,
    required String? alpns,
    required String? publicKey,
    required String? shortId,
    required String? spiderX,
  }) {
    streamSetting['security'] = streamSecurity;
    final String? normalizedSni = _blankToNull(sni);
    final String? normalizedFingerprint = _blankToNull(fingerprint);
    final String? normalizedPublicKey = _blankToNull(publicKey);
    final String? normalizedShortId = _blankToNull(shortId);
    final String? normalizedSpiderX = _blankToNull(spiderX);
    final List<String>? normalizedAlpns = _blankToNull(alpns)?.split(',');

    final Map<String, dynamic> tlsSetting = <String, dynamic>{
      'allowInsecure': allowInsecure,
      'serverName': normalizedSni,
      'alpn': normalizedAlpns,
      'minVersion': null,
      'maxVersion': null,
      'preferServerCipherSuites': null,
      'cipherSuites': null,
      'fingerprint': normalizedFingerprint,
      'certificates': null,
      'disableSystemRoot': null,
      'enableSessionResumption': null,
    };
    if (streamSecurity == 'tls') {
      streamSetting['realitySettings'] = null;
      streamSetting['tlsSettings'] = tlsSetting;
    } else if (streamSecurity == 'reality') {
      streamSetting['tlsSettings'] = null;
      streamSetting['realitySettings'] = <String, dynamic>{
        'show': false,
        'serverName': normalizedSni,
        'fingerprint': normalizedFingerprint,
        'publicKey': normalizedPublicKey,
        'shortId': normalizedShortId,
        'spiderX': normalizedSpiderX,
      };
    }
  }

  /// Removes null/empty map values recursively.
  dynamic removeNulls(dynamic params) {
    if (params is Map) {
      final Map<dynamic, dynamic> map = <dynamic, dynamic>{};
      params.forEach((key, value) {
        final dynamic compactedValue = removeNulls(value);
        if (compactedValue != null) {
          map[key] = compactedValue;
        }
      });
      if (map.isNotEmpty) {
        return map;
      }
    } else if (params is List) {
      final List<dynamic> list = <dynamic>[];
      for (final dynamic value in params) {
        final dynamic compactedValue = removeNulls(value);
        if (compactedValue != null) {
          list.add(compactedValue);
        }
      }
      if (list.isNotEmpty) {
        return list;
      }
    } else if (params != null) {
      return params;
    }
    return null;
  }

  String? _blankToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
