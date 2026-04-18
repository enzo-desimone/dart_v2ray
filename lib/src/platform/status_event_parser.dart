import '../models/connection_status.dart';

/// Converts native event-channel payloads to [ConnectionStatus].
class StatusEventParser {
  /// Parses a single event item from the `dart_v2ray/status` channel.
  static ConnectionStatus parse(dynamic event) {
    if (event is! List) {
      return const ConnectionStatus();
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

    final int? remainingAutoDisconnectSeconds =
        event.length > 6 && event[6] != null
            ? int.tryParse(event[6].toString())
            : null;

    return ConnectionStatus(
      durationSeconds: parseIntAt(0),
      uploadSpeedBytesPerSecond: parseIntAt(1),
      downloadSpeedBytesPerSecond: parseIntAt(2),
      uploadBytesTotal: parseIntAt(3),
      downloadBytesTotal: parseIntAt(4),
      state: parseStringAt(5, 'DISCONNECTED'),
      connectionPhase: parseStringAt(7, parseStringAt(5, 'DISCONNECTED')),
      transportMode: parseStringAt(8, 'idle'),
      trafficSource: parseStringAt(9),
      trafficReason: parseStringAt(10),
      isProcessRunning: parseBoolAt(11),
      remainingAutoDisconnectSeconds: remainingAutoDisconnectSeconds,
    );
  }
}
