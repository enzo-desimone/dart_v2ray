import '../../models/vpn_status.dart';

/// Parses Windows diagnostics maps and converts them to [VpnStatus].
class WindowsStatusFallbackMapper {
  /// Returns `true` when two status snapshots differ in user-facing fields.
  static bool areDifferent(VpnStatus current, VpnStatus next) {
    return current.connectionState != next.connectionState ||
        current.transportMode != next.transportMode ||
        current.trafficSource != next.trafficSource ||
        current.statusReason != next.statusReason ||
        current.processRunning != next.processRunning ||
        current.sessionSeconds != next.sessionSeconds ||
        current.uploadSpeedBps != next.uploadSpeedBps ||
        current.downloadSpeedBps != next.downloadSpeedBps ||
        current.uploadedBytes != next.uploadedBytes ||
        current.downloadedBytes != next.downloadedBytes ||
        current.autoDisconnectRemainingSeconds !=
            next.autoDisconnectRemainingSeconds;
  }

  /// Builds a best-effort [VpnStatus] from a diagnostics payload.
  static VpnStatus fromDiagnostics(
    Map<String, dynamic> diagnostics,
    VpnStatus fallback,
  ) {
    final VpnConnectionState connectionState = VpnStatus.resolveState(
      _string(diagnostics, 'state', fallback.connectionState.wireValue),
      phaseHint: _string(
        diagnostics,
        'connection_phase',
        fallback.connectionState.wireValue,
      ),
    );

    String statusReason = _string(
      diagnostics,
      'traffic_reason',
      fallback.statusReason,
    );
    if (statusReason.isEmpty && connectionState == VpnConnectionState.error) {
      statusReason = _string(
        diagnostics,
        'error_message',
        fallback.statusReason,
      );
    }

    final String remainingRaw = _string(
      diagnostics,
      'remaining_auto_disconnect_seconds',
    );
    final int? remaining =
        remainingRaw.isEmpty
            ? fallback.autoDisconnectRemainingSeconds
            : int.tryParse(remainingRaw) ??
                fallback.autoDisconnectRemainingSeconds;

    return fallback.copyWith(
      connectionState: connectionState,
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
      statusReason: statusReason,
      processRunning: _bool(
        diagnostics,
        'xray_process_running',
        fallback.processRunning,
      ),
      sessionSeconds: _int(
        diagnostics,
        'duration_seconds',
        fallback.sessionSeconds,
      ),
      uploadSpeedBps: _int(
        diagnostics,
        'upload_speed_bps',
        fallback.uploadSpeedBps,
      ),
      downloadSpeedBps: _int(
        diagnostics,
        'download_speed_bps',
        fallback.downloadSpeedBps,
      ),
      uploadedBytes: _int(
        diagnostics,
        'upload_total_bytes',
        fallback.uploadedBytes,
      ),
      downloadedBytes: _int(
        diagnostics,
        'download_total_bytes',
        fallback.downloadedBytes,
      ),
      autoDisconnectRemainingSeconds: remaining,
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
