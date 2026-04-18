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
  Timer? _windowsStatusFallbackTimer;
  DateTime? _lastNativeStatusAt;
  bool _windowsStatusFallbackPollInFlight = false;
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

  /// Windows-only diagnostics fallback.
  ///
  /// Prefer [onStatusChanged] / [latestStatus] for cross-platform status flow.
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
  /// - latest status snapshot from the persistent listener
  /// - optional direct file reads from native log paths
  ///
  /// The returned map is intentionally generic so applications can serialize it
  /// and deliver it through any transport (HTTP, email service, ticket system).
  Future<Map<String, dynamic>> buildWindowsBugReport({
    int tailMaxBytes = 16384,
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
    _lastNativeStatusAt = null;
    _persistentStatusSubscription = onStatusChanged.listen((
      ConnectionStatus status,
    ) {
      _lastNativeStatusAt = DateTime.now();
      _emitStatus(status);
    });
    _startWindowsStatusFallbackPump();
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
    _stopWindowsStatusFallbackPump();
    await _persistentStatusSubscription?.cancel();
    _persistentStatusSubscription = null;
    _lastNativeStatusAt = null;
  }

  /// Releases local stream resources created by this instance.
  Future<void> dispose() async {
    await stopPersistentStatusListener();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }

  void _emitStatus(ConnectionStatus status) {
    _latestStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _startWindowsStatusFallbackPump() {
    if (!Platform.isWindows || _windowsStatusFallbackTimer != null) {
      return;
    }

    _windowsStatusFallbackTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      if (_persistentStatusSubscription == null ||
          _statusController.isClosed ||
          _windowsStatusFallbackPollInFlight) {
        return;
      }
      _windowsStatusFallbackPollInFlight = true;
      try {
        final Map<String, dynamic> diagnostics =
            await getWindowsTrafficDiagnostics();
        if (diagnostics['supported'].toString() != 'true') {
          return;
        }

        final ConnectionStatus fromDiagnostics = _statusFromDiagnostics(
          diagnostics,
          _latestStatus,
        );
        final bool streamLooksStale =
            _lastNativeStatusAt == null ||
            DateTime.now().difference(_lastNativeStatusAt!) >
                const Duration(seconds: 6);
        final bool statusChanged = _isStatusDifferent(
          _latestStatus,
          fromDiagnostics,
        );
        final bool coreConnectionMismatch =
            _latestStatus.state != fromDiagnostics.state ||
            _latestStatus.connectionPhase != fromDiagnostics.connectionPhase ||
            _latestStatus.isProcessRunning != fromDiagnostics.isProcessRunning;

        if (statusChanged && (streamLooksStale || coreConnectionMismatch)) {
          _emitStatus(fromDiagnostics);
        }
      } catch (_) {
        // Best-effort fallback: keep stream-only mode if diagnostics fail.
      } finally {
        _windowsStatusFallbackPollInFlight = false;
      }
    });
  }

  void _stopWindowsStatusFallbackPump() {
    _windowsStatusFallbackTimer?.cancel();
    _windowsStatusFallbackTimer = null;
    _windowsStatusFallbackPollInFlight = false;
  }

  static String _diagString(
    Map<String, dynamic> diagnostics,
    String key, [
    String fallback = '',
  ]) {
    final Object? raw = diagnostics[key];
    if (raw == null) return fallback;
    final String value = raw.toString().trim();
    return value.isEmpty ? fallback : value;
  }

  static int _diagInt(
    Map<String, dynamic> diagnostics,
    String key, [
    int fallback = 0,
  ]) {
    return int.tryParse(_diagString(diagnostics, key)) ?? fallback;
  }

  static bool _diagBool(
    Map<String, dynamic> diagnostics,
    String key, [
    bool fallback = false,
  ]) {
    final String value = _diagString(diagnostics, key).toLowerCase();
    if (value == 'true' || value == '1') return true;
    if (value == 'false' || value == '0') return false;
    return fallback;
  }

  static bool _isStatusDifferent(ConnectionStatus a, ConnectionStatus b) {
    return a.state != b.state ||
        a.connectionPhase != b.connectionPhase ||
        a.transportMode != b.transportMode ||
        a.trafficSource != b.trafficSource ||
        a.trafficReason != b.trafficReason ||
        a.isProcessRunning != b.isProcessRunning ||
        a.durationSeconds != b.durationSeconds ||
        a.uploadSpeedBytesPerSecond != b.uploadSpeedBytesPerSecond ||
        a.downloadSpeedBytesPerSecond != b.downloadSpeedBytesPerSecond ||
        a.uploadBytesTotal != b.uploadBytesTotal ||
        a.downloadBytesTotal != b.downloadBytesTotal ||
        a.remainingAutoDisconnectSeconds != b.remainingAutoDisconnectSeconds;
  }

  static ConnectionStatus _statusFromDiagnostics(
    Map<String, dynamic> diagnostics,
    ConnectionStatus fallback,
  ) {
    final String state = _diagString(diagnostics, 'state', fallback.state);
    final String phase = _diagString(
      diagnostics,
      'connection_phase',
      fallback.connectionPhase.isEmpty ? state : fallback.connectionPhase,
    );
    final String transportMode = _diagString(
      diagnostics,
      'transport_mode',
      fallback.transportMode,
    );
    final String trafficSource = _diagString(
      diagnostics,
      'traffic_source',
      fallback.trafficSource,
    );
    final String trafficReason = _diagString(
      diagnostics,
      'traffic_reason',
      fallback.trafficReason,
    );
    final bool processRunning = _diagBool(
      diagnostics,
      'xray_process_running',
      fallback.isProcessRunning,
    );

    final String remainingRaw = _diagString(
      diagnostics,
      'remaining_auto_disconnect_seconds',
    );
    final int? remaining = remainingRaw.isEmpty
        ? fallback.remainingAutoDisconnectSeconds
        : int.tryParse(remainingRaw) ?? fallback.remainingAutoDisconnectSeconds;

    return fallback.copyWith(
      state: state,
      connectionPhase: phase,
      transportMode: transportMode,
      trafficSource: trafficSource,
      trafficReason: trafficReason,
      isProcessRunning: processRunning,
      durationSeconds: _diagInt(
        diagnostics,
        'duration_seconds',
        fallback.durationSeconds,
      ),
      uploadSpeedBytesPerSecond: _diagInt(
        diagnostics,
        'upload_speed_bps',
        fallback.uploadSpeedBytesPerSecond,
      ),
      downloadSpeedBytesPerSecond: _diagInt(
        diagnostics,
        'download_speed_bps',
        fallback.downloadSpeedBytesPerSecond,
      ),
      uploadBytesTotal: _diagInt(
        diagnostics,
        'upload_total_bytes',
        fallback.uploadBytesTotal,
      ),
      downloadBytesTotal: _diagInt(
        diagnostics,
        'download_total_bytes',
        fallback.downloadBytesTotal,
      ),
      remainingAutoDisconnectSeconds: remaining,
    );
  }

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
