import '../../models/connection_status.dart';

/// Parses Windows diagnostics maps and converts them to [ConnectionStatus].
class WindowsStatusFallbackMapper {
  /// Returns `true` when two status snapshots differ in user-facing fields.
  static bool areDifferent(ConnectionStatus current, ConnectionStatus next) {
    return current.state != next.state ||
        current.connectionPhase != next.connectionPhase ||
        current.transportMode != next.transportMode ||
        current.trafficSource != next.trafficSource ||
        current.trafficReason != next.trafficReason ||
        current.isProcessRunning != next.isProcessRunning ||
        current.durationSeconds != next.durationSeconds ||
        current.uploadSpeedBytesPerSecond != next.uploadSpeedBytesPerSecond ||
        current.downloadSpeedBytesPerSecond !=
            next.downloadSpeedBytesPerSecond ||
        current.uploadBytesTotal != next.uploadBytesTotal ||
        current.downloadBytesTotal != next.downloadBytesTotal ||
        current.remainingAutoDisconnectSeconds !=
            next.remainingAutoDisconnectSeconds;
  }

  /// Builds a best-effort [ConnectionStatus] from a diagnostics payload.
  static ConnectionStatus fromDiagnostics(
    Map<String, dynamic> diagnostics,
    ConnectionStatus fallback,
  ) {
    final String state = _string(diagnostics, 'state', fallback.state);
    final String phase = _string(
      diagnostics,
      'connection_phase',
      fallback.connectionPhase.isEmpty ? state : fallback.connectionPhase,
    );

    final String remainingRaw = _string(
      diagnostics,
      'remaining_auto_disconnect_seconds',
    );
    final int? remaining =
        remainingRaw.isEmpty
            ? fallback.remainingAutoDisconnectSeconds
            : int.tryParse(remainingRaw) ??
                fallback.remainingAutoDisconnectSeconds;

    return fallback.copyWith(
      state: state,
      connectionPhase: phase,
      transportMode: _string(
        diagnostics,
        'transport_mode',
        fallback.transportMode,
      ),
      trafficSource: _string(
        diagnostics,
        'traffic_source',
        fallback.trafficSource,
      ),
      trafficReason: _string(
        diagnostics,
        'traffic_reason',
        fallback.trafficReason,
      ),
      isProcessRunning: _bool(
        diagnostics,
        'xray_process_running',
        fallback.isProcessRunning,
      ),
      durationSeconds: _int(
        diagnostics,
        'duration_seconds',
        fallback.durationSeconds,
      ),
      uploadSpeedBytesPerSecond: _int(
        diagnostics,
        'upload_speed_bps',
        fallback.uploadSpeedBytesPerSecond,
      ),
      downloadSpeedBytesPerSecond: _int(
        diagnostics,
        'download_speed_bps',
        fallback.downloadSpeedBytesPerSecond,
      ),
      uploadBytesTotal: _int(
        diagnostics,
        'upload_total_bytes',
        fallback.uploadBytesTotal,
      ),
      downloadBytesTotal: _int(
        diagnostics,
        'download_total_bytes',
        fallback.downloadBytesTotal,
      ),
      remainingAutoDisconnectSeconds: remaining,
    );
  }

  static String _string(
    Map<String, dynamic> diagnostics,
    String key, [
    String fallback = '',
  ]) {
    final Object? raw = diagnostics[key];
    if (raw == null) {
      return fallback;
    }

    final String value = raw.toString().trim();
    return value.isEmpty ? fallback : value;
  }

  static int _int(
    Map<String, dynamic> diagnostics,
    String key, [
    int fallback = 0,
  ]) {
    return int.tryParse(_string(diagnostics, key)) ?? fallback;
  }

  static bool _bool(
    Map<String, dynamic> diagnostics,
    String key, [
    bool fallback = false,
  ]) {
    final String value = _string(diagnostics, key).toLowerCase();
    if (value == 'true' || value == '1') {
      return true;
    }
    if (value == 'false' || value == '0') {
      return false;
    }
    return fallback;
  }
}
