# dart_v2ray

`dart_v2ray` is a Flutter plugin that runs Xray/V2Ray as a local proxy or VPN on Android, iOS, Windows, and Linux.

It supports VLESS, VMESS, Trojan, Shadowsocks, and Socks share links, exposes a clean Dart API, and streams runtime traffic/status updates.

## Features

- Start/stop Xray connections from Flutter.
- Android + iOS VPN integration.
- Windows TUN support with optional diagnostics.
- Linux desktop support through the shared desktop core.
- Auto-disconnect timer with update/read/cancel APIs.
- Share-link parsing helpers (`vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`).
- Status stream with state, connection phase, traffic source, process health, upload/download speed, and traffic totals.

## Supported Platforms

- Android
- iOS
- Windows
- Linux

## Installation

Add the package to your app:

```yaml
dependencies:
  dart_v2ray: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:dart_v2ray/dart_v2ray.dart';

final v2ray = DartV2ray();

Future<void> connect(String configJson) async {
  await v2ray.initialize(
    providerBundleIdentifier: 'com.example.myapp',
    groupIdentifier: 'group.com.example.myapp',
  );

  final granted = await v2ray.requestPermission();
  if (!granted) return;

  await v2ray.start(
    remark: 'My profile',
    config: configJson,
    proxyOnly: false,
    windowsRequireTun: false,
  );
}
```

Listen to runtime status updates:

```dart
v2ray.startPersistentStatusListener();
v2ray.persistentStatusStream.listen((status) {
  print('state=${status.state}');
  print('phase=${status.connectionPhase}'); // CONNECTING / VERIFYING / READY / ACTIVE / ...
  print('processRunning=${status.isProcessRunning}');
  print('up=${status.uploadSpeedBytesPerSecond} down=${status.downloadSpeedBytesPerSecond}');
});
```

## Dart API Reference

### Class: `DartV2ray`

- `Future<bool> requestPermission()`
Requests runtime permission/elevation required by each platform.

- `Future<void> initialize({...})`
Initializes native components.

Parameters:
- `notificationIconResourceType`: Android notification icon resource type (default: `mipmap`).
- `notificationIconResourceName`: Android notification icon resource name (default: `ic_launcher`).
- `providerBundleIdentifier`: iOS app bundle identifier prefix used for the packet tunnel target.
- `groupIdentifier`: iOS App Group used for extension communication.
- `allowVpnFromSettings`: Android guard flag for external VPN starts.

- `Future<void> start({...})`
Starts a connection from a full Xray JSON config.

Parameters:
- `remark`: Human-readable connection label.
- `config`: Full Xray JSON object as string.
- `blockedApps`: Android blocked app package list.
- `bypassSubnets`: Subnets to bypass in VPN mode.
- `dnsServers`: Custom DNS server list.
- `proxyOnly`: Run local proxy only (no system-wide VPN route).
- `notificationDisconnectButtonName`: Android notification button text.
- `showNotificationDisconnectButton`: Android show/hide disconnect button.
- `autoDisconnect`: Auto-disconnect configuration (`AutoDisconnectConfig`).
- `windowsRequireTun`: On Windows, forces TUN behavior when available.

- `Future<void> stop()`
Stops the active connection.

- `Future<int> getServerDelay({required String config, String url})`
Measures outbound delay for the supplied config.

- `Future<int> getConnectedServerDelay({String url})`
Measures delay through the currently connected tunnel/proxy.

- `Future<String> getCoreVersion()`
Returns the native Xray core version string.

- `Future<void> configureWindowsDebugLogging({...})`
Controls Windows runtime logging for plugin logs, verbose native logs, and captured `xray.exe` stdio.

- `Future<int> updateAutoDisconnectTime(int additionalSeconds)`
Adds/removes seconds from the active timer.

- `Future<int> getRemainingAutoDisconnectTime()`
Returns remaining seconds or `-1` if disabled.

- `Future<void> cancelAutoDisconnect()`
Cancels the auto-disconnect timer.

- `Future<bool> wasAutoDisconnected()`
Returns whether the previous session ended due to timer expiry.

- `Future<void> clearAutoDisconnectFlag()`
Clears persisted auto-disconnect state.

- `Future<int> getAutoDisconnectTimestamp()`
Returns the last auto-disconnect timestamp (milliseconds since epoch).

- `Future<Map<String, dynamic>> getWindowsTrafficDiagnostics()`
Windows-only diagnostics fallback for connection phase, process state, traffic source, and counters.

- `Future<Map<String, dynamic>> getWindowsDebugLogs({int maxBytes = 16384})`
Returns Windows log paths plus the tail of the plugin log and captured Xray log.

- `Future<Map<String, dynamic>> buildWindowsBugReport({...})`
Builds a generic Windows bug-report payload with latest status snapshot, log tails, and optional log file content ready to send to your backend/API.

- `Stream<ConnectionStatus> get onStatusChanged`
Raw native status stream with connection lifecycle and traffic diagnostics fields.

- `void startPersistentStatusListener()`
Starts an internal listener that keeps the latest status snapshot even if UI listeners detach.

- `Stream<ConnectionStatus> get persistentStatusStream`
Broadcast stream backed by the persistent listener.

- `ConnectionStatus get latestStatus`
Latest status snapshot from the persistent listener.

- `Future<void> stopPersistentStatusListener()`
Stops the persistent listener.

- `Future<void> dispose()`
Releases stream resources.

### Share Link Parsing

Use `DartV2ray.parseShareLink(link)` to parse a link into a `V2rayUrl` object and build full JSON:

```dart
final parsed = DartV2ray.parseShareLink(vlessOrVmessLink);
final configJson = parsed.getFullConfiguration();
```

Supported parser classes:
- `VlessUrl`
- `VmessUrl`
- `TrojanUrl`
- `ShadowsocksUrl`
- `SocksUrl`

## Dart Models

### `AutoDisconnectConfig`

Fields:
- `durationSeconds`: Maximum session duration.
- `showRemainingTimeInNotification`: Show remaining timer in native notification.
- `timeFormat`: `AutoDisconnectTimeFormat.withSeconds` or `.withoutSeconds`.
- `onExpire`: `AutoDisconnectExpireBehavior.disconnectSilently` or `.disconnectWithNotification`.
- `expiredNotificationMessage`: Optional custom message.

### `ConnectionStatus`

Fields:
- `durationSeconds`
- `uploadSpeedBytesPerSecond`
- `downloadSpeedBytesPerSecond`
- `uploadBytesTotal`
- `downloadBytesTotal`
- `state` (`CONNECTED`, `CONNECTING`, `DISCONNECTED`, `AUTO_DISCONNECTED`)
- `connectionPhase` (`DISCONNECTED`, `CONNECTING`, `VERIFYING`, `READY`, `ACTIVE`, `AUTO_DISCONNECTED`)
- `transportMode` (for example `tun`, `proxy`, `idle`)
- `trafficSource` (for example `tun_interface`, `process_io`, `upstream_interface`, `none`)
- `trafficReason` (diagnostic reason describing the latest selection/decision)
- `isProcessRunning` (`true` when native Xray process is alive)
- `remainingAutoDisconnectSeconds`

Helpers:
- `isConnected`
- `isReady`
- `hasActiveTraffic`
- `isVerifyingConnection`
- `copyWith(...)`
- `toMap()`

### Connection State Semantics

- `state` represents the native transport state.
- `connectionPhase=CONNECTING`: startup/routing is in progress.
- `connectionPhase=VERIFYING`: process is alive and session is being confirmed.
- `connectionPhase=READY`: session is established but no traffic observed yet.
- `connectionPhase=ACTIVE`: live traffic is observed.
- `connectionPhase=AUTO_DISCONNECTED`: timer-based disconnect completed.

For robust UX, prefer `connectionPhase` plus `isProcessRunning` for connect/disconnect controls, rather than relying on speed counters alone.

## Platform Notes

### Android

- The plugin currently bundles native binaries only for `arm64-v8a` and `armeabi-v7a`.
- On `x86` / `x86_64` emulators, startup can fail because `libxray.so` is not packaged for that ABI.
- Use a physical ARM device, an ARM emulator image, or provide custom `x86/x86_64` builds for `libxray.so` and `libtun2socks.so`.

### iOS

You must provide:
- A Network Extension target (Packet Tunnel).
- Correct `providerBundleIdentifier` and `groupIdentifier`.
- Matching App Group capability in app + extension.
- An `XRay.xcframework` source for `pod install`.

The plugin does not hardcode any external framework URL.
Before running `pod install`, provide one of these options:

```bash
# Option 1: local zip path
export DART_V2RAY_IOS_FRAMEWORK_ZIP_PATH=/absolute/path/XRay.xcframework.zip

# Option 2: hosted zip + sha256
export DART_V2RAY_IOS_FRAMEWORK_URL=https://your-domain/releases/XRay.xcframework.zip
export DART_V2RAY_IOS_FRAMEWORK_SHA256=your_sha256_here
```

### Windows

The plugin does not download `xray.exe` for you. To ship it directly with your app,
place it at `windows/bin/xray.exe` inside the plugin package: the existing Windows
build step already bundles that file next to the app executable.

For Windows runtime:
- Elevated app execution (Administrator).
- `xray.exe` available via `XRAY_EXECUTABLE`, `PATH`, app directory, or plugin bundle.
- `wintun.dll` is only required for TUN mode and can be provided via `WINTUN_DLL`,
  `PATH`, or plugin bundle.

If you do not want to ship `wintun.dll`, keep `windowsRequireTun: false` and run the
core in proxy mode instead of Windows TUN mode.

Diagnostics logs can be enabled either with environment variables or directly from Dart before `initialize()` / `start()`:

```dart
await v2ray.configureWindowsDebugLogging(
  enableFileLog: true,
  enableVerboseLog: true,
  captureXrayIo: true,
  clearExistingLogs: true,
);
```

Equivalent environment variables:
- `DART_V2RAY_WINDOWS_FILE_LOG=1`
- `DART_V2RAY_WINDOWS_VERBOSE_LOG=1`
- `DART_V2RAY_WINDOWS_CAPTURE_XRAY_IO=1`

To inspect the current log tail from Flutter:

```dart
final logs = await v2ray.getWindowsDebugLogs();
print(logs['plugin_log_tail']);
print(logs['xray_log_tail']);
```

To build a full bug-report payload (including log file content) and send it to your API:

```dart
final report = await v2ray.buildWindowsBugReport(
  includeLogFiles: true,
);

// Example: send to your backend, email service, or ticket pipeline.
await http.post(
  Uri.parse('https://your-api.example.com/bug-report'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode(report),
);
```

By default the Windows temp directory is used, typically `%TEMP%\dart_v2ray.log`
and `%TEMP%\dart_v2ray_xray.log`.

The status stream now carries extended connection fields on Windows, including:
- `connectionPhase`
- `transportMode`
- `trafficSource`
- `trafficReason`
- `isProcessRunning`

These fields are useful when status looks connected but traffic is still zero (for example `connectionPhase=READY` while waiting for first traffic sample).

### Linux

Desktop support is available through the shared core. Elevation checks are not required by default.

## Example App

A plugin-focused example is available in `example/lib/main.dart` and shows:
- initialization
- permission request
- connect/disconnect
- delay checks
- status stream display with state/phase/process visibility
- Windows diagnostics popup
- optional console status logging and periodic diagnostics logging for troubleshooting

## Development

```bash
flutter pub get
dart format .
flutter analyze
flutter test
```

## License

MIT
