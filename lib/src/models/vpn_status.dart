/// Canonical lifecycle states emitted by the plugin.
enum VpnConnectionState {
  connecting('CONNECTING'),
  connected('CONNECTED'),
  disconnected('DISCONNECTED'),
  autoDisconnected('AUTO_DISCONNECTED'),
  error('ERROR');

  const VpnConnectionState(this.wireValue);

  final String wireValue;
}

/// Snapshot emitted by the native status stream.
class VpnStatus {
  /// Normalizes native status/phase combinations into the 5 public states.
  static VpnConnectionState resolveState(String rawState, {String? phaseHint}) {
    final String state = rawState.trim().toUpperCase();
    final String phase = (phaseHint ?? '').trim().toUpperCase();

    if (state == VpnConnectionState.error.wireValue ||
        phase == VpnConnectionState.error.wireValue) {
      return VpnConnectionState.error;
    }

    if (state == VpnConnectionState.autoDisconnected.wireValue ||
        phase == VpnConnectionState.autoDisconnected.wireValue) {
      return VpnConnectionState.autoDisconnected;
    }

    if (state == VpnConnectionState.disconnected.wireValue) {
      return VpnConnectionState.disconnected;
    }

    if (state == VpnConnectionState.connecting.wireValue ||
        state == 'DISCONNECTING') {
      return VpnConnectionState.connecting;
    }

    if (state == VpnConnectionState.connected.wireValue) {
      if (phase == 'VERIFYING' ||
          phase == VpnConnectionState.connecting.wireValue) {
        return VpnConnectionState.connecting;
      }
      return VpnConnectionState.connected;
    }

    if (state == 'VERIFYING') {
      return VpnConnectionState.connecting;
    }

    if (state == 'READY' || state == 'ACTIVE') {
      return VpnConnectionState.connected;
    }

    if (state.isEmpty) {
      if (phase == VpnConnectionState.connected.wireValue ||
          phase == 'READY' ||
          phase == 'ACTIVE') {
        return VpnConnectionState.connected;
      }

      if (phase == 'VERIFYING' ||
          phase == VpnConnectionState.connecting.wireValue ||
          phase == 'DISCONNECTING') {
        return VpnConnectionState.connecting;
      }

      if (phase == VpnConnectionState.autoDisconnected.wireValue) {
        return VpnConnectionState.autoDisconnected;
      }

      if (phase == VpnConnectionState.error.wireValue) {
        return VpnConnectionState.error;
      }
    }

    return VpnConnectionState.disconnected;
  }

  /// Connection duration (seconds) for the current session.
  final int sessionSeconds;

  /// Upload speed in bytes/second.
  final int uploadSpeedBps;

  /// Download speed in bytes/second.
  final int downloadSpeedBps;

  /// Total uploaded traffic in bytes for the current session.
  final int uploadedBytes;

  /// Total downloaded traffic in bytes for the current session.
  final int downloadedBytes;

  /// Canonical connection state.
  final VpnConnectionState connectionState;

  /// Transport mode selected by the native layer, such as `tun` or `proxy`.
  final String transportMode;

  /// Native traffic source used for counters, when available.
  final String trafficSource;

  /// Extra diagnostic reason describing the latest traffic/status decision.
  final String statusReason;

  /// Whether the native Xray process is currently alive.
  final bool processRunning;

  /// Remaining auto-disconnect time in seconds when enabled; otherwise `null`.
  final int? autoDisconnectRemainingSeconds;

  const VpnStatus({
    this.sessionSeconds = 0,
    this.uploadSpeedBps = 0,
    this.downloadSpeedBps = 0,
    this.uploadedBytes = 0,
    this.downloadedBytes = 0,
    this.connectionState = VpnConnectionState.disconnected,
    this.transportMode = 'idle',
    this.trafficSource = '',
    this.statusReason = '',
    this.processRunning = false,
    this.autoDisconnectRemainingSeconds,
  });

  /// Returns `true` when the connection is currently active.
  bool get isConnected => connectionState == VpnConnectionState.connected;

  /// Returns `true` while connection setup is in progress.
  bool get isConnecting => connectionState == VpnConnectionState.connecting;

  /// Returns `true` when connection is fully stopped.
  bool get isDisconnected => connectionState == VpnConnectionState.disconnected;

  /// Returns `true` when session ended by auto-disconnect timer.
  bool get isAutoDisconnected =>
      connectionState == VpnConnectionState.autoDisconnected;

  /// Returns `true` when native setup/connection failed.
  bool get isError => connectionState == VpnConnectionState.error;

  /// Returns a copy with selective overrides.
  VpnStatus copyWith({
    int? sessionSeconds,
    int? uploadSpeedBps,
    int? downloadSpeedBps,
    int? uploadedBytes,
    int? downloadedBytes,
    VpnConnectionState? connectionState,
    String? transportMode,
    String? trafficSource,
    String? statusReason,
    bool? processRunning,
    int? autoDisconnectRemainingSeconds,
  }) {
    return VpnStatus(
      sessionSeconds: sessionSeconds ?? this.sessionSeconds,
      uploadSpeedBps: uploadSpeedBps ?? this.uploadSpeedBps,
      downloadSpeedBps: downloadSpeedBps ?? this.downloadSpeedBps,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      connectionState: connectionState ?? this.connectionState,
      transportMode: transportMode ?? this.transportMode,
      trafficSource: trafficSource ?? this.trafficSource,
      statusReason: statusReason ?? this.statusReason,
      processRunning: processRunning ?? this.processRunning,
      autoDisconnectRemainingSeconds:
          autoDisconnectRemainingSeconds ?? this.autoDisconnectRemainingSeconds,
    );
  }

  /// Converts this instance to a JSON-like map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionSeconds': sessionSeconds,
      'uploadSpeedBps': uploadSpeedBps,
      'downloadSpeedBps': downloadSpeedBps,
      'uploadedBytes': uploadedBytes,
      'downloadedBytes': downloadedBytes,
      'connectionState': connectionState.wireValue,
      'transportMode': transportMode,
      'trafficSource': trafficSource,
      'statusReason': statusReason,
      'processRunning': processRunning,
      'autoDisconnectRemainingSeconds': autoDisconnectRemainingSeconds,
    };
  }
}
