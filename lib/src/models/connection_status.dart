/// Snapshot emitted by the native status stream.
class ConnectionStatus {
  /// Connection duration (seconds) for the current session.
  final int durationSeconds;

  /// Upload speed in bytes/second.
  final int uploadSpeedBytesPerSecond;

  /// Download speed in bytes/second.
  final int downloadSpeedBytesPerSecond;

  /// Total uploaded traffic in bytes for the current session.
  final int uploadBytesTotal;

  /// Total downloaded traffic in bytes for the current session.
  final int downloadBytesTotal;

  /// Native state string, for example:
  /// `CONNECTED`, `CONNECTING`, `DISCONNECTED`, `AUTO_DISCONNECTED`.
  final String state;

  /// Higher-level lifecycle phase for the current session.
  ///
  /// Typical values:
  /// `DISCONNECTED`, `CONNECTING`, `VERIFYING`, `READY`, `ACTIVE`,
  /// `AUTO_DISCONNECTED`.
  final String connectionPhase;

  /// Transport mode selected by the native layer, such as `tun` or `proxy`.
  final String transportMode;

  /// Native traffic source used for counters, when available.
  final String trafficSource;

  /// Extra diagnostic reason describing the latest traffic/status decision.
  final String trafficReason;

  /// Whether the native Xray process is currently alive.
  final bool isProcessRunning;

  /// Remaining auto-disconnect time in seconds when enabled; otherwise `null`.
  final int? remainingAutoDisconnectSeconds;

  const ConnectionStatus({
    this.durationSeconds = 0,
    this.uploadSpeedBytesPerSecond = 0,
    this.downloadSpeedBytesPerSecond = 0,
    this.uploadBytesTotal = 0,
    this.downloadBytesTotal = 0,
    this.state = 'DISCONNECTED',
    this.connectionPhase = 'DISCONNECTED',
    this.transportMode = 'idle',
    this.trafficSource = '',
    this.trafficReason = '',
    this.isProcessRunning = false,
    this.remainingAutoDisconnectSeconds,
  });

  /// Returns `true` when the connection is currently active.
  bool get isConnected => state.toUpperCase() == 'CONNECTED';

  /// Returns `true` when the connection has moved beyond setup/verification.
  bool get isReady {
    final String phase = connectionPhase.toUpperCase();
    return phase == 'READY' || phase == 'ACTIVE';
  }

  /// Returns `true` when live traffic has been observed for the session.
  bool get hasActiveTraffic => connectionPhase.toUpperCase() == 'ACTIVE';

  /// Returns `true` while the native layer is still validating the session.
  bool get isVerifyingConnection =>
      connectionPhase.toUpperCase() == 'VERIFYING';

  /// Returns a copy with selective overrides.
  ConnectionStatus copyWith({
    int? durationSeconds,
    int? uploadSpeedBytesPerSecond,
    int? downloadSpeedBytesPerSecond,
    int? uploadBytesTotal,
    int? downloadBytesTotal,
    String? state,
    String? connectionPhase,
    String? transportMode,
    String? trafficSource,
    String? trafficReason,
    bool? isProcessRunning,
    int? remainingAutoDisconnectSeconds,
  }) {
    return ConnectionStatus(
      durationSeconds: durationSeconds ?? this.durationSeconds,
      uploadSpeedBytesPerSecond:
          uploadSpeedBytesPerSecond ?? this.uploadSpeedBytesPerSecond,
      downloadSpeedBytesPerSecond:
          downloadSpeedBytesPerSecond ?? this.downloadSpeedBytesPerSecond,
      uploadBytesTotal: uploadBytesTotal ?? this.uploadBytesTotal,
      downloadBytesTotal: downloadBytesTotal ?? this.downloadBytesTotal,
      state: state ?? this.state,
      connectionPhase: connectionPhase ?? this.connectionPhase,
      transportMode: transportMode ?? this.transportMode,
      trafficSource: trafficSource ?? this.trafficSource,
      trafficReason: trafficReason ?? this.trafficReason,
      isProcessRunning: isProcessRunning ?? this.isProcessRunning,
      remainingAutoDisconnectSeconds:
          remainingAutoDisconnectSeconds ?? this.remainingAutoDisconnectSeconds,
    );
  }

  /// Converts this instance to a JSON-like map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'durationSeconds': durationSeconds,
      'uploadSpeedBytesPerSecond': uploadSpeedBytesPerSecond,
      'downloadSpeedBytesPerSecond': downloadSpeedBytesPerSecond,
      'uploadBytesTotal': uploadBytesTotal,
      'downloadBytesTotal': downloadBytesTotal,
      'state': state,
      'connectionPhase': connectionPhase,
      'transportMode': transportMode,
      'trafficSource': trafficSource,
      'trafficReason': trafficReason,
      'isProcessRunning': isProcessRunning,
      'remainingAutoDisconnectSeconds': remainingAutoDisconnectSeconds,
    };
  }
}
