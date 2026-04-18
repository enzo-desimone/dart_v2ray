import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart_v2ray_platform_interface.dart';
import 'src/models/auto_disconnect_config.dart';
import 'src/models/connection_status.dart';

/// Method-channel implementation for [DartV2rayPlatform].
class MethodChannelDartV2ray extends DartV2rayPlatform {
  /// Native command channel.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('dart_v2ray');

  /// Native status stream channel.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel('dart_v2ray/status');

  @override
  Future<void> initialize({
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
    bool allowVpnFromSettings = true,
  }) async {
    await methodChannel.invokeMethod<void>('initializeVless', <String, dynamic>{
      'notificationIconResourceType': notificationIconResourceType,
      'notificationIconResourceName': notificationIconResourceName,
      'providerBundleIdentifier': providerBundleIdentifier,
      'groupIdentifier': groupIdentifier,
      'allowVpnFromSettings': allowVpnFromSettings,
    });
  }

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
    await methodChannel.invokeMethod<void>('startVless', <String, dynamic>{
      'remark': remark,
      'config': config,
      'blocked_apps': blockedApps,
      'bypass_subnets': bypassSubnets,
      'dns_servers': dnsServers,
      'proxy_only': proxyOnly,
      'notificationDisconnectButtonName': notificationDisconnectButtonName,
      'showNotificationDisconnectButton': showNotificationDisconnectButton,
      'auto_disconnect': autoDisconnect?.toMap(),
      'windows_require_tun': windowsRequireTun,
    });
  }

  @override
  Future<void> stop() async {
    await methodChannel.invokeMethod<void>('stopVless');
  }

  @override
  Future<int> getServerDelay({
    required String config,
    required String url,
  }) async {
    return await methodChannel.invokeMethod<int>(
          'getServerDelay',
          <String, dynamic>{'config': config, 'url': url},
        ) ??
        -1;
  }

  @override
  Future<int> getConnectedServerDelay(String url) async {
    return await methodChannel.invokeMethod<int>(
          'getConnectedServerDelay',
          <String, dynamic>{'url': url},
        ) ??
        -1;
  }

  @override
  Future<bool> requestPermission() async {
    return await methodChannel.invokeMethod<bool>('requestPermission') ?? false;
  }

  @override
  Future<String> getCoreVersion() async {
    return await methodChannel.invokeMethod<String>('getCoreVersion') ??
        'unknown';
  }

  @override
  Future<void> configureWindowsDebugLogging({
    bool enableFileLog = false,
    bool enableVerboseLog = false,
    bool captureXrayIo = false,
    bool clearExistingLogs = false,
  }) async {
    try {
      await methodChannel.invokeMethod<void>(
        'configureWindowsDebugLogging',
        <String, dynamic>{
          'enable_file_log': enableFileLog,
          'enable_verbose_log': enableVerboseLog,
          'capture_xray_io': captureXrayIo,
          'clear_existing_logs': clearExistingLogs,
        },
      );
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<int> updateAutoDisconnectTime(int additionalSeconds) async {
    return await methodChannel.invokeMethod<int>(
          'updateAutoDisconnectTime',
          <String, dynamic>{'additional_seconds': additionalSeconds},
        ) ??
        -1;
  }

  @override
  Future<int> getRemainingAutoDisconnectTime() async {
    return await methodChannel.invokeMethod<int>(
          'getRemainingAutoDisconnectTime',
        ) ??
        -1;
  }

  @override
  Future<void> cancelAutoDisconnect() async {
    await methodChannel.invokeMethod<void>('cancelAutoDisconnect');
  }

  @override
  Future<bool> wasAutoDisconnected() async {
    return await methodChannel.invokeMethod<bool>('wasAutoDisconnected') ??
        false;
  }

  @override
  Future<void> clearAutoDisconnectFlag() async {
    await methodChannel.invokeMethod<void>('clearAutoDisconnectFlag');
  }

  @override
  Future<int> getAutoDisconnectTimestamp() async {
    return await methodChannel.invokeMethod<int>(
          'getAutoDisconnectTimestamp',
        ) ??
        0;
  }

  @override
  Future<Map<String, dynamic>> getWindowsTrafficDiagnostics() async {
    try {
      final Object? raw = await methodChannel.invokeMethod<Object?>(
        'getWindowsTrafficSource',
      );
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{
        'supported': false,
        'reason': 'missing_plugin_implementation',
      };
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'supported': false,
        'reason': error.code,
        'message': error.message ?? '',
      };
    }
  }

  @override
  Future<Map<String, dynamic>> getWindowsDebugLogs({
    int maxBytes = 16384,
  }) async {
    try {
      final Object? raw = await methodChannel.invokeMethod<Object?>(
        'getWindowsDebugLogs',
        <String, dynamic>{'max_bytes': maxBytes},
      );
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{
        'supported': false,
        'reason': 'missing_plugin_implementation',
      };
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'supported': false,
        'reason': error.code,
        'message': error.message ?? '',
      };
    }
  }

  @override
  Stream<ConnectionStatus> get onStatusChanged {
    return eventChannel.receiveBroadcastStream().map(_parseStatusEvent);
  }

  ConnectionStatus _parseStatusEvent(dynamic event) {
    if (event is! List) {
      return const ConnectionStatus();
    }

    int parseAt(int index) {
      if (index >= event.length) return 0;
      return int.tryParse(event[index].toString()) ?? 0;
    }

    String stringAt(int index, [String fallback = '']) {
      if (index >= event.length || event[index] == null) return fallback;
      final String value = event[index].toString();
      return value.isEmpty ? fallback : value;
    }

    bool boolAt(int index, [bool fallback = false]) {
      if (index >= event.length || event[index] == null) return fallback;
      final String value = event[index].toString().toLowerCase();
      if (value == 'true' || value == '1') return true;
      if (value == 'false' || value == '0') return false;
      return fallback;
    }

    final int? remaining =
        event.length > 6 && event[6] != null
            ? int.tryParse(event[6].toString())
            : null;

    return ConnectionStatus(
      durationSeconds: parseAt(0),
      uploadSpeedBytesPerSecond: parseAt(1),
      downloadSpeedBytesPerSecond: parseAt(2),
      uploadBytesTotal: parseAt(3),
      downloadBytesTotal: parseAt(4),
      state: stringAt(5, 'DISCONNECTED'),
      connectionPhase: stringAt(7, stringAt(5, 'DISCONNECTED')),
      transportMode: stringAt(8, 'idle'),
      trafficSource: stringAt(9),
      trafficReason: stringAt(10),
      isProcessRunning: boolAt(11),
      remainingAutoDisconnectSeconds: remaining,
    );
  }
}
