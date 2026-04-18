import 'dart:async';
import 'dart:convert';

import 'package:dart_v2ray/dart_v2ray.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String _integratedTestShareLink =
    'vless://80cbd2e5-ceca-4f3c-9566-e39c2cb3719f@94.177.201.17:443'
    '?security=reality&type=tcp&headerType=&flow=xtls-rprx-vision'
    '&path=&host=&sni=yandex.ru&fp=chrome'
    '&pbk=eF1_pRWT5VDYbkEY3EzHTwXDQx1qD1f7aDJcHVxLK1M&sid=6ba87f12'
    '#VieraVPN%20Marz%20%28260994604%29%20%5BVLESS%20-%20tcp%5D';
const String _integratedTestRemark = 'VieraVPN Marz (260994604) [VLESS - tcp]';

void main() {
  runApp(const DartV2rayExampleApp());
}

class DartV2rayExampleApp extends StatelessWidget {
  const DartV2rayExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dart_v2ray Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DartV2rayHomePage(),
    );
  }
}

class DartV2rayHomePage extends StatefulWidget {
  const DartV2rayHomePage({super.key});

  @override
  State<DartV2rayHomePage> createState() => _DartV2rayHomePageState();
}

class _DartV2rayHomePageState extends State<DartV2rayHomePage> {
  final DartV2ray _v2ray = DartV2ray();
  final TextEditingController _shareLinkController = TextEditingController(
    text: _integratedTestShareLink,
  );
  final TextEditingController _remarkController = TextEditingController(
    text: _integratedTestRemark,
  );
  final TextEditingController _configController = TextEditingController(
    text: '{}',
  );

  StreamSubscription<ConnectionStatus>? _statusSubscription;
  ConnectionStatus _status = const ConnectionStatus();

  bool _requireTun = false;
  bool _initialized = false;
  bool _isInitializing = false;
  bool _isRequestingPermission = false;
  bool _isStarting = false;
  bool _isStopping = false;
  bool _isCheckingDelay = false;
  bool _isResettingLogs = false;
  bool _isShowingLogs = false;
  bool _consoleStatusLogsEnabled = true;
  String _coreVersion = '-';

  @override
  void initState() {
    super.initState();
    unawaited(
      _enableWindowsDebugLogging(
        clearExistingLogs: true,
        showFeedback: false,
        trackBusy: false,
      ),
    );
    _v2ray.startPersistentStatusListener();
    _statusSubscription = _v2ray.persistentStatusStream.listen((status) {
      if (!mounted) return;
      _logStatusToConsole(status);
      setState(() {
        _status = status;
      });
    });
    _loadIntegratedTestShareLink(showFeedback: false);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _shareLinkController.dispose();
    _remarkController.dispose();
    _configController.dispose();
    unawaited(_v2ray.dispose());
    super.dispose();
  }

  String get _normalizedState {
    final String normalized = _status.state.trim().toUpperCase();
    return normalized.isEmpty ? 'DISCONNECTED' : normalized;
  }

  String get _connectionPhase {
    final String phase = _status.connectionPhase.trim().toUpperCase();
    return phase.isEmpty ? _normalizedState : phase;
  }

  String get _trafficSourceLabel {
    final String source = _status.trafficSource.trim();
    return source.isEmpty ? 'Waiting for traffic' : _humanizeState(source);
  }

  bool get _isConnected => _status.isConnected;

  bool get _isConnecting => _normalizedState == 'CONNECTING';

  bool get _isConnectedByPhase =>
      _connectionPhase == 'VERIFYING' ||
      _connectionPhase == 'READY' ||
      _connectionPhase == 'ACTIVE';

  bool get _isConnectedEffective => _isConnected || _isConnectedByPhase;

  bool get _hasLiveSession =>
      _isConnecting || _isConnectedEffective || _status.isProcessRunning;

  bool get _canEditConfiguration =>
      !_isInitializing && !_isStarting && !_isStopping && !_hasLiveSession;

  bool get _canInitialize =>
      !_initialized && !_isInitializing && !_isStarting && !_hasLiveSession;

  bool get _canRequestPermission =>
      !_isRequestingPermission &&
      !_isInitializing &&
      !_isStarting &&
      !_isStopping;

  bool get _canDisconnect => _initialized && !_isInitializing && !_isStopping;

  bool get _canResetLogs =>
      !_isResettingLogs && !_isInitializing && !_isStarting && !_isStopping;

  bool get _canShowLogs =>
      !_isShowingLogs && !_isInitializing && !_isStarting && !_isStopping;

  String get _modeSummary {
    if (_requireTun) {
      return 'Desktop TUN required';
    }
    return 'Proxy only';
  }

  String get _statusHeadline {
    if (_isInitializing) {
      return 'Initializing plugin';
    }
    if (!_initialized) {
      return 'Initialization required';
    }
    if (_isStarting || _isConnecting || _connectionPhase == 'CONNECTING') {
      return 'Connection in progress';
    }
    if (_connectionPhase == 'VERIFYING') {
      return 'Verifying connection';
    }
    if (_connectionPhase == 'READY') {
      return 'Connected and waiting for traffic';
    }
    if (_connectionPhase == 'ACTIVE') {
      return 'Traffic detected';
    }
    if (_connectionPhase == 'AUTO_DISCONNECTED') {
      return 'Session ended automatically';
    }
    if (_isConnectedEffective) {
      return 'Connection active';
    }
    if (_configValidationError != null) {
      return 'Configuration needs attention';
    }
    return 'Ready to connect';
  }

  String get _statusSupportingText {
    if (!_initialized) {
      return 'Initialize the plugin first so the native runtime and bundled Xray core are ready.';
    }
    if (_isStarting || _isConnecting || _connectionPhase == 'CONNECTING') {
      return 'The app is requesting permission, starting Xray, and preparing the tunnel.';
    }
    if (_connectionPhase == 'VERIFYING') {
      return 'Xray is running in ${_status.transportMode} mode and the session is being confirmed. Speeds can stay at 0 until the first status sample is ready.';
    }
    if (_connectionPhase == 'READY') {
      return 'The connection is established in ${_status.transportMode} mode, but no live traffic has been observed yet.';
    }
    if (_connectionPhase == 'ACTIVE') {
      return 'Traffic is flowing via ${_trafficSourceLabel.toLowerCase()}. Speeds update continuously while the session remains active.';
    }
    if (_connectionPhase == 'AUTO_DISCONNECTED') {
      return 'The last session stopped automatically. You can reconnect or inspect the logs.';
    }
    if (_isConnectedEffective) {
      return 'The session is marked connected, but traffic has not been classified yet.';
    }
    final String? configError = _configValidationError;
    if (configError != null) {
      return configError;
    }
    return 'The current config looks valid. You can request permission and connect when ready.';
  }

  String? get _currentActionLabel {
    if (_isInitializing) {
      return 'Preparing native plugin runtime';
    }
    if (_isRequestingPermission) {
      return 'Requesting VPN permission';
    }
    if (_isStarting) {
      return 'Starting Xray session';
    }
    if (_isStopping) {
      return 'Stopping active session';
    }
    if (_isCheckingDelay) {
      return 'Measuring server delay';
    }
    if (_isResettingLogs) {
      return 'Refreshing Windows debug logs';
    }
    if (_isShowingLogs) {
      return 'Loading captured logs';
    }
    if (_isConnecting) {
      return 'Waiting for the tunnel to come up';
    }
    return null;
  }

  String get _primaryActionHint {
    if (!_initialized) {
      return 'Start with Initialize. Connect stays disabled until the plugin is ready.';
    }
    if (_hasLiveSession) {
      return 'The configuration is locked while a session is active to avoid editing a live connection by mistake.';
    }
    if (_configValidationError != null) {
      return 'Fix the configuration below to enable Connect.';
    }
    return 'Everything is ready. Connect will request permission automatically if needed.';
  }

  bool _canConnect(String? configValidationError) {
    return _initialized &&
        !_isInitializing &&
        !_isStarting &&
        !_isStopping &&
        !_isCheckingDelay &&
        !_hasLiveSession &&
        configValidationError == null;
  }

  bool _canCheckDelay(String? configValidationError) {
    return _initialized &&
        !_isInitializing &&
        !_isStarting &&
        !_isStopping &&
        !_isCheckingDelay &&
        !_isConnecting &&
        (_isConnectedEffective || configValidationError == null);
  }

  Future<void> _initialize() async {
    if (!_canInitialize) return;

    setState(() {
      _isInitializing = true;
    });

    try {
      await _v2ray.initialize(
        providerBundleIdentifier: 'com.example.dartV2rayExample',
        groupIdentifier: 'group.com.example.dartV2rayExample',
      );
      final String coreVersion = await _v2ray.getCoreVersion();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _coreVersion = coreVersion;
      });
      _showMessage('Plugin initialized');
    } catch (error) {
      _showMessage('Initialize failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    if (!_canRequestPermission) return;

    setState(() {
      _isRequestingPermission = true;
    });

    try {
      final bool granted = await _v2ray.requestPermission();
      _showMessage(granted ? 'Permission granted' : 'Permission denied');
    } catch (error) {
      _showMessage('Permission request failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermission = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    final String? configError = _configValidationError;
    if (configError != null) {
      _showMessage(configError);
      return;
    }
    if (!_initialized) {
      _showMessage('Initialize the plugin first.');
      return;
    }
    if (_hasLiveSession) {
      _showMessage('A session is already active.');
      return;
    }

    setState(() {
      _isStarting = true;
    });

    try {
      final bool granted = await _v2ray.requestPermission();
      if (!granted) {
        _showMessage('Permission denied');
        return;
      }

      await _v2ray.start(
        remark: _remarkController.text.trim(),
        config: _configController.text,
        requireTun: _requireTun,
      );
      _showMessage('Connection started');
    } catch (error) {
      debugPrint('Start failed: $error');
      _showMessage('Start failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    if (!_canDisconnect) return;

    setState(() {
      _isStopping = true;
    });

    try {
      await _v2ray.stop();
      _showMessage('Connection stopped');
    } catch (error) {
      _showMessage('Stop failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStopping = false;
        });
      }
    }
  }

  Future<void> _checkDelay() async {
    final String? configError = _configValidationError;
    if (!_canCheckDelay(configError)) return;

    setState(() {
      _isCheckingDelay = true;
    });

    try {
      final int delay = _status.isConnected
          ? await _v2ray.getConnectedServerDelay()
          : await _v2ray.getServerDelay(config: _configController.text);
      _showMessage('Delay: ${delay}ms');
    } catch (error) {
      _showMessage('Delay check failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingDelay = false;
        });
      }
    }
  }

  Future<void> _enableWindowsDebugLogging({
    bool clearExistingLogs = true,
    bool showFeedback = true,
    bool trackBusy = true,
  }) async {
    if (trackBusy && !_canResetLogs) return;

    if (trackBusy) {
      setState(() {
        _isResettingLogs = true;
      });
    }

    try {
      await _v2ray.configureWindowsDebugLogging(
        enableFileLog: true,
        enableVerboseLog: true,
        captureXrayIo: true,
        clearExistingLogs: clearExistingLogs,
      );
      if (showFeedback) {
        _showMessage('Windows debug logging enabled');
      }
    } catch (error) {
      if (showFeedback) {
        _showMessage('Enabling logs failed: $error');
      }
    } finally {
      if (trackBusy && mounted) {
        setState(() {
          _isResettingLogs = false;
        });
      }
    }
  }

  Future<void> _showWindowsDebugLogs() async {
    if (!_canShowLogs) return;

    setState(() {
      _isShowingLogs = true;
    });

    try {
      final Map<String, dynamic> logs = await _v2ray.getWindowsDebugLogs();
      if (!mounted) return;

      final String lines = logs.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n\n');

      if (_consoleStatusLogsEnabled) {
        debugPrint('[dart_v2ray][logs] BEGIN');
        debugPrint(lines);
        debugPrint('[dart_v2ray][logs] END');
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Windows Debug Logs'),
            content: SingleChildScrollView(child: Text(lines)),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: lines));
                  Navigator.of(dialogContext).pop();
                  _showMessage('Windows debug logs copied');
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isShowingLogs = false;
        });
      }
    }
  }

  void _applyShareLink({
    bool showFeedback = true,
    String fallbackRemark = 'Imported share link',
  }) {
    final String raw = _shareLinkController.text.trim();
    if (raw.isEmpty) {
      if (showFeedback) {
        _showMessage('Share link is required.');
      }
      return;
    }

    try {
      final V2rayUrl parsed = DartV2ray.parseShareLink(raw);
      final String parsedRemark = parsed.remark.trim();

      setState(() {
        _remarkController.text = parsedRemark.isEmpty
            ? fallbackRemark
            : parsedRemark;
        _configController.text = parsed.getFullConfiguration();
      });

      if (showFeedback) {
        _showMessage('Share link imported');
      }
    } catch (error) {
      if (showFeedback) {
        _showMessage('Share link import failed: $error');
      }
    }
  }

  void _loadIntegratedTestShareLink({bool showFeedback = true}) {
    _shareLinkController.text = _integratedTestShareLink;
    _applyShareLink(
      showFeedback: showFeedback,
      fallbackRemark: _integratedTestRemark,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _logStatusToConsole(ConnectionStatus status) {
    if (!_consoleStatusLogsEnabled) return;
    final String timestamp = DateTime.now().toIso8601String();
    debugPrint(
      '[dart_v2ray][status][$timestamp] '
      'state=${status.state} '
      'phase=${status.connectionPhase} '
      'mode=${status.transportMode} '
      'processRunning=${status.isProcessRunning} '
      'trafficSource=${status.trafficSource} '
      'trafficReason=${status.trafficReason} '
      'up=${status.uploadSpeedBytesPerSecond}B/s '
      'down=${status.downloadSpeedBytesPerSecond}B/s '
      'upTotal=${status.uploadBytesTotal}B '
      'downTotal=${status.downloadBytesTotal}B '
      'duration=${status.durationSeconds}s',
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatDuration(int seconds) {
    final Duration duration = Duration(seconds: seconds);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
    }
    return '${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  String _humanizeState(String rawState) {
    return rawState
        .replaceAll('-', '_')
        .toLowerCase()
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String? get _shareLinkValidationError {
    final String raw = _shareLinkController.text.trim();
    if (raw.isEmpty) {
      return 'Share link is required.';
    }

    try {
      DartV2ray.parseShareLink(raw);
    } catch (_) {
      return 'Share link must be a supported V2Ray/Xray URL.';
    }

    return null;
  }

  String? get _configValidationError {
    final String raw = _configController.text.trim();
    if (raw.isEmpty) {
      return 'Config is required.';
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return 'Config must be a JSON object.';
      }

      final dynamic outbounds = decoded['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) {
        return 'Config must contain at least one outbound.';
      }
    } on FormatException {
      return 'Config must be valid JSON.';
    } catch (_) {
      return 'Config must be valid JSON.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? shareLinkValidationError = _shareLinkValidationError;
    final String? configValidationError = _configValidationError;
    final bool canConnect = _canConnect(configValidationError);
    final bool canCheckDelay = _canCheckDelay(configValidationError);

    return Scaffold(
      appBar: AppBar(title: const Text('dart_v2ray example')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusOverviewCard(
              headline: _statusHeadline,
              supportingText: _statusSupportingText,
              currentActionLabel: _currentActionLabel,
              initialized: _initialized,
              coreVersion: _coreVersion,
              statusLabel: _humanizeState(_normalizedState),
              rawPhase: _connectionPhase,
              phaseLabel: _humanizeState(_connectionPhase),
              rawState: _normalizedState,
              modeSummary: _modeSummary,
              transportModeLabel: _humanizeState(_status.transportMode),
              trafficSourceLabel: _trafficSourceLabel,
              processStateLabel: _status.isProcessRunning
                  ? 'Running'
                  : 'Not running',
              durationLabel: _formatDuration(_status.durationSeconds),
              uploadLabel: _formatBytes(_status.uploadBytesTotal),
              downloadLabel: _formatBytes(_status.downloadBytesTotal),
              uploadSpeedLabel:
                  '${_formatBytes(_status.uploadSpeedBytesPerSecond)}/s',
              downloadSpeedLabel:
                  '${_formatBytes(_status.downloadSpeedBytesPerSecond)}/s',
              remainingAutoDisconnectSeconds:
                  _status.remainingAutoDisconnectSeconds,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _primaryActionHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: canConnect ? _connect : null,
                          icon: Icon(
                            (_isStarting || _isConnecting)
                                ? Icons.hourglass_bottom_rounded
                                : (_isConnectedEffective
                                      ? Icons.check_circle_rounded
                                      : Icons.play_arrow_rounded),
                          ),
                          label: Text(
                            (_isStarting || _isConnecting)
                                ? 'Connecting...'
                                : (_isConnectedEffective
                                      ? 'Connected'
                                      : 'Connect'),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _canDisconnect ? _disconnect : null,
                          icon: Icon(
                            _isStopping
                                ? Icons.hourglass_bottom_rounded
                                : Icons.stop_circle_rounded,
                          ),
                          label: Text(
                            _isStopping ? 'Disconnecting...' : 'Disconnect',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canInitialize ? _initialize : null,
                          icon: Icon(
                            _initialized
                                ? Icons.check_circle_rounded
                                : (_isInitializing
                                      ? Icons.hourglass_bottom_rounded
                                      : Icons.power_settings_new_rounded),
                          ),
                          label: Text(
                            _initialized
                                ? 'Initialized'
                                : (_isInitializing
                                      ? 'Initializing...'
                                      : 'Initialize'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canRequestPermission
                              ? _requestPermission
                              : null,
                          icon: Icon(
                            _isRequestingPermission
                                ? Icons.hourglass_bottom_rounded
                                : Icons.verified_user_rounded,
                          ),
                          label: Text(
                            _isRequestingPermission
                                ? 'Requesting...'
                                : 'Permission',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: canCheckDelay ? _checkDelay : null,
                          icon: Icon(
                            _isCheckingDelay
                                ? Icons.hourglass_bottom_rounded
                                : Icons.speed_rounded,
                          ),
                          label: Text(
                            _isCheckingDelay ? 'Checking...' : 'Delay',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Link',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _canEditConfiguration
                          ? 'Importing rewrites the JSON config below from the share link.'
                          : 'Configuration edits are disabled while the session is active.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _shareLinkController,
                      enabled: _canEditConfiguration,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Share link',
                        helperText:
                            'Supported schemes: vless, vmess, trojan, ss, socks.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ).copyWith(errorText: shareLinkValidationError),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _canEditConfiguration &&
                                  shareLinkValidationError == null
                              ? _applyShareLink
                              : null,
                          icon: const Icon(Icons.file_download_done_rounded),
                          label: const Text('Import share link'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canEditConfiguration
                              ? _loadIntegratedTestShareLink
                              : null,
                          icon: const Icon(Icons.bolt_rounded),
                          label: const Text('Use integrated test link'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuration',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Remark and JSON config are what the session uses when Connect is pressed.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _remarkController,
                      enabled: _canEditConfiguration,
                      decoration: const InputDecoration(
                        labelText: 'Remark',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _configController,
                      enabled: _canEditConfiguration,
                      minLines: 8,
                      maxLines: 12,
                      style: const TextStyle(fontFamily: 'monospace'),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Xray JSON config',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ).copyWith(errorText: configValidationError),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _requireTun,
                      onChanged: _canEditConfiguration
                          ? (value) => setState(() => _requireTun = value)
                          : null,
                      title: const Text('Require TUN mode'),
                      subtitle: const Text(
                        'On: full-device TUN. Off: proxy-only mode.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Windows Tools',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use these when you need captured plugin/Xray logs.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _consoleStatusLogsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _consoleStatusLogsEnabled = value;
                        });
                        _showMessage(
                          value
                              ? 'Console status logs enabled'
                              : 'Console status logs disabled',
                        );
                      },
                      title: const Text('Console status logs'),
                      subtitle: const Text(
                        'Print the live status stream to the debug console.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _canResetLogs
                              ? () => _enableWindowsDebugLogging()
                              : null,
                          icon: Icon(
                            _isResettingLogs
                                ? Icons.hourglass_bottom_rounded
                                : Icons.restart_alt_rounded,
                          ),
                          label: Text(
                            _isResettingLogs
                                ? 'Resetting logs...'
                                : 'Reset logs',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canShowLogs
                              ? _showWindowsDebugLogs
                              : null,
                          icon: Icon(
                            _isShowingLogs
                                ? Icons.hourglass_bottom_rounded
                                : Icons.receipt_long_rounded,
                          ),
                          label: Text(
                            _isShowingLogs ? 'Loading logs...' : 'Show logs',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusOverviewCard extends StatelessWidget {
  const _StatusOverviewCard({
    required this.headline,
    required this.supportingText,
    required this.currentActionLabel,
    required this.initialized,
    required this.coreVersion,
    required this.statusLabel,
    required this.rawPhase,
    required this.phaseLabel,
    required this.rawState,
    required this.modeSummary,
    required this.transportModeLabel,
    required this.trafficSourceLabel,
    required this.processStateLabel,
    required this.durationLabel,
    required this.uploadLabel,
    required this.downloadLabel,
    required this.uploadSpeedLabel,
    required this.downloadSpeedLabel,
    required this.remainingAutoDisconnectSeconds,
  });

  final String headline;
  final String supportingText;
  final String? currentActionLabel;
  final bool initialized;
  final String coreVersion;
  final String statusLabel;
  final String rawPhase;
  final String phaseLabel;
  final String rawState;
  final String modeSummary;
  final String transportModeLabel;
  final String trafficSourceLabel;
  final String processStateLabel;
  final String durationLabel;
  final String uploadLabel;
  final String downloadLabel;
  final String uploadSpeedLabel;
  final String downloadSpeedLabel;
  final int? remainingAutoDisconnectSeconds;

  Color _tone(ColorScheme scheme) {
    switch (rawPhase) {
      case 'ACTIVE':
        return Colors.green;
      case 'CONNECTING':
      case 'VERIFYING':
        return Colors.orange;
      case 'READY':
        return Colors.teal;
      case 'CONNECTED':
      case 'CONNECTED_IDLE':
        return Colors.green;
      case 'AUTO_DISCONNECTED':
        return Colors.deepOrange;
      default:
        break;
    }

    switch (rawState) {
      case 'CONNECTED':
        return Colors.green;
      case 'CONNECTING':
        return Colors.orange;
      case 'AUTO_DISCONNECTED':
        return Colors.deepOrange;
      default:
        return scheme.primary;
    }
  }

  IconData _icon() {
    switch (rawPhase) {
      case 'ACTIVE':
        return Icons.shield_rounded;
      case 'CONNECTING':
      case 'VERIFYING':
        return Icons.sync_rounded;
      case 'READY':
        return Icons.wifi_tethering_rounded;
      case 'AUTO_DISCONNECTED':
        return Icons.timelapse_rounded;
      default:
        break;
    }

    switch (rawState) {
      case 'CONNECTED':
        return Icons.shield_rounded;
      case 'CONNECTING':
        return Icons.sync_rounded;
      case 'AUTO_DISCONNECTED':
        return Icons.timelapse_rounded;
      default:
        return Icons.wifi_tethering_off_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color tone = _tone(scheme);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          colors: <Color>[tone.withValues(alpha: 0.15), scheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(_icon(), color: tone),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusPill(label: statusLabel, tone: tone),
                      const SizedBox(height: 10),
                      Text(
                        headline,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        supportingText,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (currentActionLabel != null) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                currentActionLabel!,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                borderRadius: BorderRadius.circular(999),
                minHeight: 8,
                color: tone,
                backgroundColor: tone.withValues(alpha: 0.12),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  label: 'Plugin',
                  value: initialized ? 'Ready' : 'Not ready',
                ),
                _InfoChip(label: 'Core', value: coreVersion),
                _InfoChip(label: 'State', value: statusLabel),
                _InfoChip(label: 'Phase', value: phaseLabel),
                _InfoChip(label: 'Mode', value: modeSummary),
                _InfoChip(label: 'Transport', value: transportModeLabel),
                _InfoChip(label: 'Traffic', value: trafficSourceLabel),
                _InfoChip(label: 'Process', value: processStateLabel),
                if (remainingAutoDisconnectSeconds != null)
                  _InfoChip(
                    label: 'Auto disconnect',
                    value: '${remainingAutoDisconnectSeconds}s',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusMetricTile(
                  label: 'Duration',
                  value: durationLabel,
                  icon: Icons.schedule_rounded,
                ),
                _StatusMetricTile(
                  label: 'Upload',
                  value: uploadLabel,
                  icon: Icons.north_rounded,
                ),
                _StatusMetricTile(
                  label: 'Download',
                  value: downloadLabel,
                  icon: Icons.south_rounded,
                ),
                _StatusMetricTile(
                  label: 'Upload speed',
                  value: uploadSpeedLabel,
                  icon: Icons.trending_up_rounded,
                ),
                _StatusMetricTile(
                  label: 'Download speed',
                  value: downloadSpeedLabel,
                  icon: Icons.trending_down_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMetricTile extends StatelessWidget {
  const _StatusMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.labelMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: tone,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
