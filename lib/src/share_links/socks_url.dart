import 'dart:convert';

import 'v2ray_url.dart';

/// Parser for `socks://` share links.
class SocksUrl extends V2rayUrl {
  SocksUrl({required super.url}) {
    if (!url.startsWith('socks://')) {
      throw ArgumentError('url is invalid');
    }

    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      throw ArgumentError('url is invalid');
    }
    uri = parsedUri;

    if (uri.userInfo.isNotEmpty) {
      final String userPass = utf8.decode(base64Decode(uri.userInfo));
      username = userPass.split(':')[0];
      password = userPass.substring(username!.length + 1);
    } else {
      username = null;
      password = null;
    }
  }

  /// Parsed URI for this share link.
  late final Uri uri;

  /// Optional username for authenticated SOCKS servers.
  late final String? username;

  /// Optional password for authenticated SOCKS servers.
  late final String? password;

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => <String, dynamic>{
    'protocol': 'socks',
    'settings': <String, dynamic>{
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'address': address,
          'level': level,
          'method': 'chacha20-poly1305',
          'ota': false,
          'password': '',
          'port': port,
          'users': <Map<String, dynamic>>[
            <String, dynamic>{
              'level': level,
              'user': username,
              'pass': password,
            },
          ],
        },
      ],
    },
    'streamSettings': streamSetting,
    'tag': 'proxy',
    'mux': <String, dynamic>{'concurrency': 8, 'enabled': false},
  };
}
