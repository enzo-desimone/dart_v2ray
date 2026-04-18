import 'dart:async';
import 'dart:io';

import '../../models/connection_status.dart';
import 'windows_status_fallback_mapper.dart';

/// Maintains a persistent connection-status stream independent from UI listeners.
///
/// This controller keeps the latest status snapshot available even when UI
/// subscriptions are disposed and reattached.
class PersistentStatusController {
  PersistentStatusController({
    required this.statusStreamFactory,
    required this.windowsDiagnosticsFetcher,
  });

  /// Factory for the native status stream.
  final Stream<ConnectionStatus> Function() statusStreamFactory;

  /// Windows-only diagnostics fetcher used as stale-stream fallback.
  final Future<Map<String, dynamic>> Function() windowsDiagnosticsFetcher;

  StreamSubscription<ConnectionStatus>? _nativeStatusSubscription;
  Timer? _windowsStatusFallbackTimer;
  DateTime? _lastNativeStatusAt;
  bool _windowsStatusFallbackPollInFlight = false;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _latestStatus = const ConnectionStatus();

  /// Last status snapshot observed by this controller.
  ConnectionStatus get latestStatus => _latestStatus;

  /// Broadcast status stream. Starts listening lazily on first access.
  Stream<ConnectionStatus> get stream {
    start();
    return _statusController.stream;
  }

  /// Starts listening to native status updates.
  void start() {
    if (_nativeStatusSubscription != null || _statusController.isClosed) {
      return;
    }

    _lastNativeStatusAt = null;
    _nativeStatusSubscription = statusStreamFactory().listen((status) {
      _lastNativeStatusAt = DateTime.now();
      _emitStatus(status);
    });
    _startWindowsStatusFallbackPump();
  }

  /// Stops listening to native status updates.
  Future<void> stop() async {
    _stopWindowsStatusFallbackPump();
    await _nativeStatusSubscription?.cancel();
    _nativeStatusSubscription = null;
    _lastNativeStatusAt = null;
  }

  /// Releases stream resources.
  Future<void> dispose() async {
    await stop();
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
      if (_nativeStatusSubscription == null ||
          _statusController.isClosed ||
          _windowsStatusFallbackPollInFlight) {
        return;
      }

      _windowsStatusFallbackPollInFlight = true;
      try {
        final Map<String, dynamic> diagnostics =
            await windowsDiagnosticsFetcher();
        if (diagnostics['supported'].toString() != 'true') {
          return;
        }

        final ConnectionStatus fromDiagnostics =
            WindowsStatusFallbackMapper.fromDiagnostics(
              diagnostics,
              _latestStatus,
            );

        final bool streamLooksStale =
            _lastNativeStatusAt == null ||
            DateTime.now().difference(_lastNativeStatusAt!) >
                const Duration(seconds: 6);
        final bool statusChanged = WindowsStatusFallbackMapper.areDifferent(
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
}
