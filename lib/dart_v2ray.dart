import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart_v2ray_platform_interface.dart';
import 'src/models/auto_disconnect_config.dart';
import 'src/models/connection_status.dart';
import 'url/shadowsocks.dart';
import 'url/socks.dart';
import 'url/trojan.dart';
import 'url/url.dart';
import 'url/vless.dart';
import 'url/vmess.dart';

export 'src/models/auto_disconnect_config.dart';
export 'src/models/connection_status.dart';
export 'url/url.dart';
export 'url/vless.dart';
export 'url/vmess.dart';
export 'url/trojan.dart';
export 'url/shadowsocks.dart';
export 'url/socks.dart';

/// High-level API for managing V2Ray/Xray connections from Flutter.
class DartV2ray {
  StreamSubscription<ConnectionStatus>? _persistentStatusSubscription;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _latestStatus = const ConnectionStatus();

  /// Requests required VPN permission (Android) or elevation checks (desktop).
  Future<bool> requestPermission() {
    return DartV2rayPlatform.instance.requestPermission();
  }

  /// Initializes native components.
  ///
  /// [providerBundleIdentifier] and [groupIdentifier] are required for iOS
  /// network-extension integration.
  Future<void> initialize({
    String notificationIconResourceType = 'mipmap',
    String notificationIconResourceName = 'ic_launcher',
    String providerBundleIdentifier = '',
    String groupIdentifier = '',
    bool allowVpnFromSettings = true,
  }) {
    return DartV2rayPlatform.instance.initialize(
      notificationIconResourceType: notificationIconResourceType,
      notificationIconResourceName: notificationIconResourceName,
      providerBundleIdentifier: providerBundleIdentifier,
      groupIdentifier: groupIdentifier,
      allowVpnFromSettings: allowVpnFromSettings,
    );
  }

  /// Starts a connection with a full Xray JSON configuration.
  ///
  /// Set [proxyOnly] to `true` to run local proxy mode without system-wide VPN.
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    List<String>? dnsServers,
    bool proxyOnly = false,
    String notificationDisconnectButtonName = 'DISCONNECT',
    bool showNotificationDisconnectButton = true,
    AutoDisconnectConfig? autoDisconnect,
    bool windowsRequireTun = false,
  }) async {
    _ensureValidJson(config);
    await DartV2rayPlatform.instance.start(
      remark: remark,
      config: config,
      blockedApps: blockedApps,
      bypassSubnets: bypassSubnets,
      dnsServers: dnsServers,
      proxyOnly: proxyOnly,
      notificationDisconnectButtonName: notificationDisconnectButtonName,
      showNotificationDisconnectButton: showNotificationDisconnectButton,
      autoDisconnect: autoDisconnect,
      windowsRequireTun: windowsRequireTun,
    );
  }

  /// Stops the active connection.
  Future<void> stop() {
    return DartV2rayPlatform.instance.stop();
  }

  /// Measures outbound delay in milliseconds using a provided config.
  Future<int> getServerDelay({
    required String config,
    String url = 'https://google.com/generate_204',
  }) async {
    _ensureValidJson(config);
    return DartV2rayPlatform.instance.getServerDelay(config: config, url: url);
  }

  /// Measures delay in milliseconds for the currently connected server.
  Future<int> getConnectedServerDelay({
    String url = 'https://google.com/generate_204',
  }) {
    return DartV2rayPlatform.instance.getConnectedServerDelay(url);
  }

  /// Returns Xray core version string.
  Future<String> getCoreVersion() {
    return DartV2rayPlatform.instance.getCoreVersion();
  }

  /// Configures Windows debug logging at runtime.
  Future<void> configureWindowsDebugLogging({
    bool enableFileLog = false,
    bool enableVerboseLog = false,
    bool captureXrayIo = false,
    bool clearExistingLogs = false,
  }) {
    return DartV2rayPlatform.instance.configureWindowsDebugLogging(
      enableFileLog: enableFileLog,
      enableVerboseLog: enableVerboseLog,
      captureXrayIo: captureXrayIo,
      clearExistingLogs: clearExistingLogs,
    );
  }

  /// Adds or subtracts seconds from the active auto-disconnect timer.
  Future<int> updateAutoDisconnectTime(int additionalSeconds) {
    return DartV2rayPlatform.instance.updateAutoDisconnectTime(
      additionalSeconds,
    );
  }

  /// Returns remaining auto-disconnect seconds, or `-1` if disabled.
  Future<int> getRemainingAutoDisconnectTime() {
    return DartV2rayPlatform.instance.getRemainingAutoDisconnectTime();
  }

  /// Cancels active auto-disconnect.
  Future<void> cancelAutoDisconnect() {
    return DartV2rayPlatform.instance.cancelAutoDisconnect();
  }

  /// Returns whether the last session ended by auto-disconnect.
  Future<bool> wasAutoDisconnected() {
    return DartV2rayPlatform.instance.wasAutoDisconnected();
  }

  /// Clears persisted auto-disconnect state.
  Future<void> clearAutoDisconnectFlag() {
    return DartV2rayPlatform.instance.clearAutoDisconnectFlag();
  }

  /// Returns auto-disconnect timestamp in milliseconds since epoch.
  Future<int> getAutoDisconnectTimestamp() {
    return DartV2rayPlatform.instance.getAutoDisconnectTimestamp();
  }

  /// Returns Windows-only diagnostics to troubleshoot connection state,
  /// traffic counters, and source selection.
  Future<Map<String, dynamic>> getWindowsTrafficDiagnostics() {
    return DartV2rayPlatform.instance.getWindowsTrafficDiagnostics();
  }

  /// Returns Windows-only plugin/xray log tails.
  Future<Map<String, dynamic>> getWindowsDebugLogs({int maxBytes = 16384}) {
    return DartV2rayPlatform.instance.getWindowsDebugLogs(maxBytes: maxBytes);
  }

  /// Builds a Windows bug-report payload ready to send to your backend/API.
  ///
  /// This method combines:
  /// - windows debug log tails from native side
  /// - windows traffic diagnostics
  /// - latest status snapshot from the persistent listener
  /// - optional direct file reads from native log paths
  ///
  /// The returned map is intentionally generic so applications can serialize it
  /// and deliver it through any transport (HTTP, email service, ticket system).
  Future<Map<String, dynamic>> buildWindowsBugReport({
    int tailMaxBytes = 16384,
    bool includeTrafficDiagnostics = true,
    bool includeLatestStatus = true,
    bool includeLogFiles = true,
    int fullLogMaxBytes = 262144,
  }) async {
    final int boundedTailBytes = tailMaxBytes.clamp(1024, 262144).toInt();
    final int boundedFullLogBytes = fullLogMaxBytes.clamp(4096, 1048576).toInt();

    final Map<String, dynamic> report = <String, dynamic>{
      'schema_version': 1,
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'platform': <String, dynamic>{
        'operating_system': Platform.operatingSystem,
        'operating_system_version': Platform.operatingSystemVersion,
      },
      'windows_supported': Platform.isWindows,
      'tail_max_bytes': boundedTailBytes,
      'full_log_max_bytes': boundedFullLogBytes,
    };

    if (!Platform.isWindows) {
      report['reason'] = 'windows_only';
      return report;
    }

    final Map<String, dynamic> windowsLogs = await getWindowsDebugLogs(
      maxBytes: boundedTailBytes,
    );
    report['windows_debug_logs'] = windowsLogs;

    if (includeTrafficDiagnostics) {
      report['windows_traffic_diagnostics'] =
          await getWindowsTrafficDiagnostics();
    }

    if (includeLatestStatus) {
      report['latest_status'] = latestStatus.toMap();
    }

    if (includeLogFiles) {
      report['windows_log_files'] = await _readWindowsLogFiles(
        windowsLogs,
        maxBytes: boundedFullLogBytes,
      );
    }

    return report;
  }

  /// Parses a share link into a config builder object.
  ///
  /// Supported schemes: `vmess://`, `vless://`, `trojan://`, `ss://`, `socks://`.
  static V2rayUrl parseShareLink(String link) {
    switch (link.split('://')[0].toLowerCase()) {
      case 'vmess':
        return VmessUrl(url: link);
      case 'vless':
        return VlessUrl(url: link);
      case 'trojan':
        return TrojanUrl(url: link);
      case 'ss':
        return ShadowsocksUrl(url: link);
      case 'socks':
        return SocksUrl(url: link);
      default:
        throw ArgumentError('Unsupported link scheme.');
    }
  }

  /// Native connection status stream.
  ///
  /// Events include base traffic counters/state and, on supported platforms,
  /// higher-level lifecycle diagnostics such as connection phase and
  /// process health.
  Stream<ConnectionStatus> get onStatusChanged {
    return DartV2rayPlatform.instance.onStatusChanged;
  }

  /// Starts a persistent status listener that survives UI subscription changes.
  void startPersistentStatusListener() {
    if (_persistentStatusSubscription != null || _statusController.isClosed) {
      return;
    }
    _persistentStatusSubscription = onStatusChanged.listen((
      ConnectionStatus status,
    ) {
      _latestStatus = status;
      if (!_statusController.isClosed) {
        _statusController.add(status);
      }
    });
  }

  /// Broadcast status stream backed by the persistent listener.
  Stream<ConnectionStatus> get persistentStatusStream {
    startPersistentStatusListener();
    return _statusController.stream;
  }

  /// Last status snapshot observed by the persistent listener.
  ConnectionStatus get latestStatus => _latestStatus;

  /// Stops the persistent status listener.
  Future<void> stopPersistentStatusListener() async {
    await _persistentStatusSubscription?.cancel();
    _persistentStatusSubscription = null;
  }

  /// Releases local stream resources created by this instance.
  Future<void> dispose() async {
    await stopPersistentStatusListener();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }

  /// Legacy alias for [initialize].
  Future<void> initializeVless({
    String notificationIconResourceType = 'mipmap',
    String notificationIconResourceName = 'ic_launcher',
    String providerBundleIdentifier = '',
    String groupIdentifier = '',
    bool allowVpnFromSettings = true,
  }) {
    return initialize(
      notificationIconResourceType: notificationIconResourceType,
      notificationIconResourceName: notificationIconResourceName,
      providerBundleIdentifier: providerBundleIdentifier,
      groupIdentifier: groupIdentifier,
      allowVpnFromSettings: allowVpnFromSettings,
    );
  }

  /// Legacy alias for [start].
  Future<void> startVless({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    List<String>? dnsServers,
    bool proxyOnly = false,
    String notificationDisconnectButtonName = 'DISCONNECT',
    bool showNotificationDisconnectButton = true,
    AutoDisconnectConfig? autoDisconnect,
    bool windowsRequireTun = false,
  }) {
    return start(
      remark: remark,
      config: config,
      blockedApps: blockedApps,
      bypassSubnets: bypassSubnets,
      dnsServers: dnsServers,
      proxyOnly: proxyOnly,
      notificationDisconnectButtonName: notificationDisconnectButtonName,
      showNotificationDisconnectButton: showNotificationDisconnectButton,
      autoDisconnect: autoDisconnect,
      windowsRequireTun: windowsRequireTun,
    );
  }

  /// Legacy alias for [stop].
  Future<void> stopVless() => stop();

  /// Legacy alias for [getWindowsTrafficDiagnostics].
  Future<Map<String, dynamic>> getWindowsTrafficSource() {
    return getWindowsTrafficDiagnostics();
  }

  /// Legacy alias for [parseShareLink].
  static V2rayUrl parseFromURL(String link) => parseShareLink(link);

  static Future<Map<String, dynamic>> _readWindowsLogFiles(
    Map<String, dynamic> windowsLogs, {
    required int maxBytes,
  }) async {
    final String pluginLogPath =
        windowsLogs['plugin_log_path']?.toString() ?? '';
    final String xrayLogPath = windowsLogs['xray_log_path']?.toString() ?? '';

    return <String, dynamic>{
      'plugin_log': await _readLogFileTail(pluginLogPath, maxBytes: maxBytes),
      'xray_log': await _readLogFileTail(xrayLogPath, maxBytes: maxBytes),
    };
  }

  static Future<Map<String, dynamic>> _readLogFileTail(
    String path, {
    required int maxBytes,
  }) async {
    if (path.isEmpty) {
      return <String, dynamic>{
        'path': path,
        'exists': false,
        'error': 'empty_path',
      };
    }

    final File file = File(path);
    try {
      final bool exists = await file.exists();
      if (!exists) {
        return <String, dynamic>{
          'path': path,
          'exists': false,
          'error': 'file_not_found',
        };
      }

      final int fileSize = await file.length();
      final int bytesToRead = min(fileSize, maxBytes);

      final RandomAccessFile handle = await file.open(mode: FileMode.read);
      try {
        await handle.setPosition(fileSize - bytesToRead);
        final List<int> data = await handle.read(bytesToRead);
        return <String, dynamic>{
          'path': path,
          'exists': true,
          'file_size_bytes': fileSize,
          'bytes_read': data.length,
          'truncated': fileSize > bytesToRead,
          'content': utf8.decode(data, allowMalformed: true),
        };
      } finally {
        await handle.close();
      }
    } catch (error) {
      return <String, dynamic>{
        'path': path,
        'exists': false,
        'error': error.toString(),
      };
    }
  }

  static void _ensureValidJson(String config) {
    try {
      final dynamic decoded = jsonDecode(config);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final dynamic outbounds = decoded['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) {
        throw ArgumentError(
          'The provided config must contain at least one outbound.',
        );
      }
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw ArgumentError(
        'The provided config must be a valid Xray JSON object with at least one outbound.',
      );
    }
  }
}
