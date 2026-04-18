import '../models/auto_disconnect_config.dart';
import '../models/connection_status.dart';
import '../platform/dart_v2ray_platform.dart';
import '../share_links/shadowsocks_url.dart';
import '../share_links/socks_url.dart';
import '../share_links/trojan_url.dart';
import '../share_links/v2ray_url.dart';
import '../share_links/vless_url.dart';
import '../share_links/vmess_url.dart';
import 'config_validator.dart';
import 'status/persistent_status_controller.dart';
import 'windows/windows_bug_report_builder.dart';

/// High-level API for managing V2Ray/Xray connections from Flutter.
class DartV2ray {
  DartV2ray()
    : _persistentStatusController = PersistentStatusController(
        statusStreamFactory: () => DartV2rayPlatform.instance.onStatusChanged,
        windowsDiagnosticsFetcher:
            () => DartV2rayPlatform.instance.getWindowsTrafficDiagnostics(),
      );

  final PersistentStatusController _persistentStatusController;

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
  /// Set [requireTun] to control connection mode:
  /// - `true`: require full-device/system TUN routing.
  /// - `false`: run proxy-only mode.
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    List<String>? dnsServers,
    bool requireTun = false,
    String notificationDisconnectButtonName = 'DISCONNECT',
    bool showNotificationDisconnectButton = true,
    AutoDisconnectConfig? autoDisconnect,
  }) async {
    validateXrayConfig(config);
    await DartV2rayPlatform.instance.start(
      remark: remark,
      config: config,
      blockedApps: blockedApps,
      bypassSubnets: bypassSubnets,
      dnsServers: dnsServers,
      requireTun: requireTun,
      notificationDisconnectButtonName: notificationDisconnectButtonName,
      showNotificationDisconnectButton: showNotificationDisconnectButton,
      autoDisconnect: autoDisconnect,
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
    validateXrayConfig(config);
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
  /// - Windows debug log tails from native side
  /// - Latest status snapshot from the persistent listener
  /// - Optional direct file reads from native log paths
  ///
  /// The returned map is intentionally generic so applications can serialize it
  /// and deliver it through any transport (HTTP, email service, ticket system).
  Future<Map<String, dynamic>> buildWindowsBugReport({
    int tailMaxBytes = 16384,
    bool includeLatestStatus = true,
    bool includeLogFiles = true,
    int fullLogMaxBytes = 262144,
  }) {
    return WindowsBugReportBuilder.build(
      debugLogsFetcher:
          ({int maxBytes = 16384}) => getWindowsDebugLogs(maxBytes: maxBytes),
      latestStatus: latestStatus,
      tailMaxBytes: tailMaxBytes,
      includeLatestStatus: includeLatestStatus,
      includeLogFiles: includeLogFiles,
      fullLogMaxBytes: fullLogMaxBytes,
    );
  }

  /// Parses a share link into a config builder object.
  ///
  /// Supported schemes: `vmess://`, `vless://`, `trojan://`, `ss://`, `socks://`.
  static V2rayUrl parseShareLink(String link) {
    switch (_extractScheme(link)) {
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
    _persistentStatusController.start();
  }

  /// Broadcast status stream backed by the persistent listener.
  Stream<ConnectionStatus> get persistentStatusStream {
    return _persistentStatusController.stream;
  }

  /// Last status snapshot observed by the persistent listener.
  ConnectionStatus get latestStatus => _persistentStatusController.latestStatus;

  /// Stops the persistent status listener.
  Future<void> stopPersistentStatusListener() {
    return _persistentStatusController.stop();
  }

  /// Releases local stream resources created by this instance.
  Future<void> dispose() {
    return _persistentStatusController.dispose();
  }

  static String _extractScheme(String link) {
    final Uri? parsed = Uri.tryParse(link);
    if (parsed != null && parsed.scheme.isNotEmpty) {
      return parsed.scheme.toLowerCase();
    }

    final int separator = link.indexOf('://');
    if (separator <= 0) {
      return '';
    }
    return link.substring(0, separator).toLowerCase();
  }
}
