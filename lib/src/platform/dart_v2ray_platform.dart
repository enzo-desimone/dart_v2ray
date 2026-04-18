import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/auto_disconnect_config.dart';
import '../models/connection_status.dart';
import 'method_channel_dart_v2ray.dart';

/// Platform interface used by the public `DartV2ray` API.
///
/// Implementations for Android/iOS/Linux/Windows are provided through the
/// method/event channels of this plugin.
abstract class DartV2rayPlatform extends PlatformInterface {
  DartV2rayPlatform() : super(token: _token);

  static final Object _token = Object();

  static DartV2rayPlatform _instance = MethodChannelDartV2ray();

  /// Active platform implementation.
  static DartV2rayPlatform get instance => _instance;

  /// Registers a custom platform implementation.
  static set instance(DartV2rayPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Requests required runtime permissions (VPN/notification where applicable).
  Future<bool> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Initializes native resources for connection management.
  Future<void> initialize({
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
    bool allowVpnFromSettings = true,
  }) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Starts a connection from an Xray JSON config.
  ///
  /// [requireTun] controls routing mode:
  /// - `true`: require full-device/system TUN routing.
  /// - `false`: run proxy-only mode.
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
  }) {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Stops the active connection.
  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Measures delay (ms) for a provided config.
  Future<int> getServerDelay({required String config, required String url}) {
    throw UnimplementedError('getServerDelay() has not been implemented.');
  }

  /// Measures delay (ms) for the active connection path.
  Future<int> getConnectedServerDelay(String url) {
    throw UnimplementedError(
      'getConnectedServerDelay() has not been implemented.',
    );
  }

  /// Returns the Xray core version from native side.
  Future<String> getCoreVersion() {
    throw UnimplementedError('getCoreVersion() has not been implemented.');
  }

  /// Windows-only runtime logging controls.
  Future<void> configureWindowsDebugLogging({
    bool enableFileLog = false,
    bool enableVerboseLog = false,
    bool captureXrayIo = false,
    bool clearExistingLogs = false,
  }) {
    throw UnimplementedError(
      'configureWindowsDebugLogging() has not been implemented.',
    );
  }

  /// Adds (or subtracts) seconds from the auto-disconnect timer.
  Future<int> updateAutoDisconnectTime(int additionalSeconds) {
    throw UnimplementedError(
      'updateAutoDisconnectTime() has not been implemented.',
    );
  }

  /// Reads remaining auto-disconnect time in seconds.
  Future<int> getRemainingAutoDisconnectTime() {
    throw UnimplementedError(
      'getRemainingAutoDisconnectTime() has not been implemented.',
    );
  }

  /// Cancels the active auto-disconnect timer.
  Future<void> cancelAutoDisconnect() {
    throw UnimplementedError(
      'cancelAutoDisconnect() has not been implemented.',
    );
  }

  /// Returns `true` when a past session ended by auto-disconnect.
  Future<bool> wasAutoDisconnected() {
    throw UnimplementedError('wasAutoDisconnected() has not been implemented.');
  }

  /// Clears the persisted auto-disconnect flag.
  Future<void> clearAutoDisconnectFlag() {
    throw UnimplementedError(
      'clearAutoDisconnectFlag() has not been implemented.',
    );
  }

  /// Timestamp (ms since epoch) of the latest auto-disconnect event.
  Future<int> getAutoDisconnectTimestamp() {
    throw UnimplementedError(
      'getAutoDisconnectTimestamp() has not been implemented.',
    );
  }

  /// Windows-only diagnostics fallback for connection phase, traffic source,
  /// process state, and counters.
  Future<Map<String, dynamic>> getWindowsTrafficDiagnostics() {
    throw UnimplementedError(
      'getWindowsTrafficDiagnostics() has not been implemented.',
    );
  }

  /// Windows-only access to plugin/xray log tails.
  Future<Map<String, dynamic>> getWindowsDebugLogs({int maxBytes = 16384}) {
    throw UnimplementedError('getWindowsDebugLogs() has not been implemented.');
  }

  /// Native status event stream.
  ///
  /// Implementations may include extended lifecycle fields in addition to
  /// base state/speed counters.
  Stream<ConnectionStatus> get onStatusChanged {
    throw UnimplementedError('onStatusChanged() has not been implemented.');
  }
}
