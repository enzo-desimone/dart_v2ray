import 'dart:convert';

import 'package:dart_v2ray/dart_v2ray.dart';
import 'package:dart_v2ray/dart_v2ray_method_channel.dart';
import 'package:dart_v2ray/dart_v2ray_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeDartV2rayPlatform extends DartV2rayPlatform
    with MockPlatformInterfaceMixin {
  bool requestPermissionResult = true;
  bool startCalled = false;

  @override
  Future<void> initialize({
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
    bool allowVpnFromSettings = true,
  }) async {}

  @override
  Future<void> start({
    required String remark,
    required String config,
    required String notificationDisconnectButtonName,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    List<String>? dnsServers,
    bool proxyOnly = false,
    bool showNotificationDisconnectButton = true,
    AutoDisconnectConfig? autoDisconnect,
    bool windowsRequireTun = false,
  }) async {
    startCalled = true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<int> getServerDelay({
    required String config,
    required String url,
  }) async {
    return 100;
  }

  @override
  Future<int> getConnectedServerDelay(String url) async {
    return 50;
  }

  @override
  Future<bool> requestPermission() async {
    return requestPermissionResult;
  }

  @override
  Future<String> getCoreVersion() async {
    return 'xray test';
  }

  @override
  Future<void> configureWindowsDebugLogging({
    bool enableFileLog = false,
    bool enableVerboseLog = false,
    bool captureXrayIo = false,
    bool clearExistingLogs = false,
  }) async {}

  @override
  Future<int> updateAutoDisconnectTime(int additionalSeconds) async {
    return additionalSeconds;
  }

  @override
  Future<int> getRemainingAutoDisconnectTime() async {
    return -1;
  }

  @override
  Future<void> cancelAutoDisconnect() async {}

  @override
  Future<bool> wasAutoDisconnected() async {
    return false;
  }

  @override
  Future<void> clearAutoDisconnectFlag() async {}

  @override
  Future<int> getAutoDisconnectTimestamp() async {
    return 0;
  }

  @override
  Future<Map<String, dynamic>> getWindowsTrafficDiagnostics() async {
    return <String, dynamic>{'supported': false};
  }

  @override
  Future<Map<String, dynamic>> getWindowsDebugLogs({int maxBytes = 16384}) async {
    return <String, dynamic>{'supported': false, 'maxBytes': maxBytes};
  }

  @override
  Stream<ConnectionStatus> get onStatusChanged {
    return Stream<ConnectionStatus>.value(const ConnectionStatus());
  }
}

void main() {
  final DartV2rayPlatform initialPlatform = DartV2rayPlatform.instance;

  test('$MethodChannelDartV2ray is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDartV2ray>());
  });

  test('requestPermission delegates to platform interface', () async {
    final plugin = DartV2ray();
    final fakePlatform = FakeDartV2rayPlatform();
    DartV2rayPlatform.instance = fakePlatform;

    expect(await plugin.requestPermission(), isTrue);
  });

  test('start validates JSON and forwards start call', () async {
    final plugin = DartV2ray();
    final fakePlatform = FakeDartV2rayPlatform();
    DartV2rayPlatform.instance = fakePlatform;

    await plugin.start(remark: 'test', config: '{}');

    expect(fakePlatform.startCalled, isTrue);
  });

  test('start throws on invalid JSON', () async {
    final plugin = DartV2ray();

    expect(
      () => plugin.start(remark: 'test', config: '{invalid-json'),
      throwsArgumentError,
    );
  });

  test('parseShareLink returns the expected parser type', () {
    final parsed = DartV2ray.parseShareLink(
      'vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?type=tcp#demo',
    );

    expect(parsed, isA<VlessUrl>());
  });

  test('parseShareLink builds VLESS reality configs without VMess-only fields', () {
    final parsed = DartV2ray.parseShareLink(
      'vless://123e4567-e89b-12d3-a456-426614174000@example.com:443'
      '?security=reality&type=tcp&flow=xtls-rprx-vision&sni=yandex.ru'
      '&fp=chrome&pbk=test-public-key&sid=6ba87f12#demo',
    );

    final Map<String, dynamic> config =
        jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;
    final Map<String, dynamic> outbound =
        (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
    final Map<String, dynamic> settings =
        outbound['settings'] as Map<String, dynamic>;
    final Map<String, dynamic> vnext =
        (settings['vnext'] as List<dynamic>).first as Map<String, dynamic>;
    final Map<String, dynamic> user =
        (vnext['users'] as List<dynamic>).first as Map<String, dynamic>;
    final Map<String, dynamic> streamSettings =
        outbound['streamSettings'] as Map<String, dynamic>;
    final Map<String, dynamic> realitySettings =
        streamSettings['realitySettings'] as Map<String, dynamic>;

    expect(outbound['protocol'], 'vless');
    expect(user['id'], '123e4567-e89b-12d3-a456-426614174000');
    expect(user['encryption'], 'none');
    expect(user['flow'], 'xtls-rprx-vision');
    expect(user.containsKey('security'), isFalse);
    expect(user.containsKey('alterId'), isFalse);
    expect(streamSettings['security'], 'reality');
    expect(streamSettings.containsKey('tlsSettings'), isFalse);
    expect(realitySettings['serverName'], 'yandex.ru');
    expect(realitySettings['fingerprint'], 'chrome');
    expect(realitySettings['publicKey'], 'test-public-key');
    expect(realitySettings['shortId'], '6ba87f12');
    expect(realitySettings.containsKey('allowInsecure'), isFalse);
    expect(realitySettings.containsKey('alpn'), isFalse);
  });
}
