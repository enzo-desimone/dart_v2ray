import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/auto_disconnect_config.dart';
import '../models/vpn_status.dart';
import 'dart_v2ray_platform.dart';
import 'status_event_parser.dart';

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
    bool requireTun = false,
    bool showNotificationDisconnectButton = true,
    AutoDisconnectConfig? autoDisconnect,
  }) async {
    await methodChannel.invokeMethod<void>('startVless', <String, dynamic>{
      'remark': remark,
      'config': config,
      'blocked_apps': blockedApps,
      'bypass_subnets': bypassSubnets,
      'dns_servers': dnsServers,
      'require_tun': requireTun,
      'notificationDisconnectButtonName': notificationDisconnectButtonName,
      'showNotificationDisconnectButton': showNotificationDisconnectButton,
      'auto_disconnect': autoDisconnect?.toMap(),
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
      await methodChannel
          .invokeMethod<void>('configureWindowsDebugLogging', <String, dynamic>{
            'enable_file_log': enableFileLog,
            'enable_verbose_log': enableVerboseLog,
            'capture_xray_io': captureXrayIo,
            'clear_existing_logs': clearExistingLogs,
          });
    } on MissingPluginException {
      // Graceful no-op on platforms without this method.
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
  Future<Map<String, dynamic>> getDesktopDebugLogs({
    int maxBytes = 16384,
  }) async {
    try {
      final Object? raw = await methodChannel.invokeMethod<Object?>(
        'getDesktopDebugLogs',
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
  Stream<VpnStatus> get onStatusChanged {
    return eventChannel.receiveBroadcastStream().map(StatusEventParser.parse);
  }
}
