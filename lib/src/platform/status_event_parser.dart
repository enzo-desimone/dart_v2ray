import '../models/vpn_status.dart';

/// Converts native event-channel payloads to [VpnStatus].
class StatusEventParser {
  /// Parses a single event item from the `dart_v2ray/status` channel.
  static VpnStatus parse(dynamic event) {
    if (event is! List) {
      return const VpnStatus();
    }

    int parseIntAt(int index) {
      if (index >= event.length) {
        return 0;
      }
      return int.tryParse(event[index].toString()) ?? 0;
    }

    String parseStringAt(int index, [String fallback = '']) {
      if (index >= event.length || event[index] == null) {
        return fallback;
      }

      final String value = event[index].toString();
      return value.isEmpty ? fallback : value;
    }

    bool parseBoolAt(int index, [bool fallback = false]) {
      if (index >= event.length || event[index] == null) {
        return fallback;
      }

      final String value = event[index].toString().toLowerCase();
      if (value == 'true' || value == '1') {
        return true;
      }
      if (value == 'false' || value == '0') {
        return false;
      }
      return fallback;
    }

    final int? autoDisconnectRemainingSeconds =
        event.length > 6 && event[6] != null
            ? int.tryParse(event[6].toString())
            : null;

    final VpnConnectionState connectionState = VpnStatus.resolveState(
      parseStringAt(5, VpnConnectionState.disconnected.wireValue),
      phaseHint: parseStringAt(7),
    );

    return VpnStatus(
      sessionSeconds: parseIntAt(0),
      uploadSpeedBps: parseIntAt(1),
      downloadSpeedBps: parseIntAt(2),
      uploadedBytes: parseIntAt(3),
      downloadedBytes: parseIntAt(4),
      connectionState: connectionState,
      transportMode: parseStringAt(8, 'idle'),
      trafficSource: parseStringAt(9),
      statusReason: parseStringAt(10),
      processRunning: parseBoolAt(11),
      autoDisconnectRemainingSeconds: autoDisconnectRemainingSeconds,
    );
  }
}
