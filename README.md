# dart_v2ray

`dart_v2ray` is a Flutter plugin to manage Xray/V2Ray connections from Dart.
It supports proxy and VPN workflows, runtime status streaming,
auto-disconnect, and share-link parsing (`vless://`, `vmess://`, `trojan://`,
`ss://`, `socks://`).

## What You Get

- Single high-level API: `DartV2ray`.
- Cross-platform support for Android, iOS, Windows, Linux, and macOS.
- Runtime connection status stream (`onStatusChanged`) plus persistent listener.
- Auto-disconnect timer controls.
- Windows diagnostics and bug-report builder helpers.
- Share-link parsing into full Xray JSON configs.

## Platform Matrix

| Platform | Plugin Status | Runtime Source | Native Setup Summary |
| --- | --- | --- | --- |
| Android | Available, tested | Bundled (`arm64-v8a`, `armeabi-v7a`) | VPN permission flow (`requestPermission`) |
| iOS | Available | `XRay.xcframework` auto-download at `pod install` (override supported) | Packet Tunnel target + App Group + matching identifiers |
| Windows | Available, tested | Auto-download `Xray-windows-64.zip` at CMake configure | Run as Administrator for TUN workflows |
| Linux | Available (not fully team-validated) | Runtime binaries must be reachable in deployment | Environment/package permissions depend on distro |
| macOS | Available | Manual runtime files (`xray`, `geoip.dat`, `geosite.dat`) | Proxy mode minimal; TUN needs Packet Tunnel + App Group + `Tun2SocksKit` |

## Installation

```yaml
dependencies:
  dart_v2ray: ^0.1.0
```

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:dart_v2ray/dart_v2ray.dart';

final DartV2ray v2ray = DartV2ray();

Future<void> connect(String configJson) async {
  await v2ray.initialize(
    providerBundleIdentifier: 'com.example.myapp',
    groupIdentifier: 'group.com.example.myapp',
  );

  final bool granted = await v2ray.requestPermission();
  if (!granted) return;

  await v2ray.start(
    remark: 'My profile',
    config: configJson,
    requireTun: true,
  );
}
```

`requireTun` behavior:
- Android, Windows, Linux, macOS:
  `true` requests TUN mode, `false` keeps proxy-only mode.
- iOS:
  Packet Tunnel extension flow is used (no proxy-only switch today).

## API Overview

Main class:
- `DartV2ray`

Connection lifecycle:
- `initialize(...)`
- `requestPermission()`
- `start(...)`
- `stop()`

Network diagnostics:
- `getServerDelay(...)`
- `getConnectedServerDelay(...)`
- `getCoreVersion()`

Desktop diagnostics:
- `configureWindowsDebugLogging(...)`
- `getWindowsTrafficDiagnostics()`
- `getDesktopDebugLogs(...)`
- `buildWindowsBugReport(...)`

Auto-disconnect:
- `updateAutoDisconnectTime(...)`
- `getRemainingAutoDisconnectTime()`
- `cancelAutoDisconnect()`
- `wasAutoDisconnected()`
- `clearAutoDisconnectFlag()`
- `getAutoDisconnectTimestamp()`

Status stream:
- `onStatusChanged`
- `startPersistentStatusListener()`
- `persistentStatusStream`
- `latestStatus`
- `stopPersistentStatusListener()`
- `dispose()`

Canonical `VpnStatus.connectionState` values:
- `CONNECTING`: native startup/tunnel preparation in progress.
- `CONNECTED`: session active.
- `DISCONNECTED`: session stopped.
- `AUTO_DISCONNECTED`: session ended by auto-disconnect timer.
- `ERROR`: startup/runtime failure detected.

For diagnostics, keep using `transportMode`, `trafficSource`, `statusReason`,
and `processRunning`.

Share-link parsing:

```dart
final V2rayUrl parsed = DartV2ray.parseShareLink(link);
final String configJson = parsed.getFullConfiguration();
```

## Native Setup Checklist

Android:
- Call `requestPermission()` before `start(...)`.
- If you test on emulator, prefer ARM images unless you bundle x86/x64 libs.

iOS:
- Add Packet Tunnel Network Extension target.
- Configure a shared App Group for app + extension.
- Pass matching `providerBundleIdentifier` and `groupIdentifier` to
  `initialize(...)`.
- `XRay.xcframework` is downloaded automatically by default at `pod install`.
  You can override source/hash with `DART_V2RAY_IOS_FRAMEWORK_*`.

Windows:
- App should run with Administrator privileges for TUN/VPN flows.
- Runtime is downloaded automatically by default and bundled as:
  `xray.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`.
- You can override source/hash with `DART_V2RAY_WINDOWS_XRAY_*` and
  `DART_V2RAY_XRAY_VERSION`.

Linux:
- Ensure Xray runtime binaries/libraries are reachable in your final package.
- For `requireTun: true`, extra capabilities/permissions may be needed
  depending on distro/package format.

macOS:
- Provide runtime files manually before `pod install`:
  `macos/bin/xray`, `macos/bin/geoip.dat`, `macos/bin/geosite.dat`.
- Alternatively, set `DART_V2RAY_MACOS_RUNTIME_DIR` to a folder containing
  `xray`, `geoip.dat`, and `geosite.dat`.
- For TUN mode (`requireTun: true`), add Packet Tunnel extension,
  configure shared App Group, and link `Tun2SocksKit` to extension target.
- Ensure extension target includes `xray`, `geoip.dat`, `geosite.dat`
  in extension resources.

## Documentation Hub

- [Documentation Index](docs/README.md)
- [Android Guide](docs/platforms/android/README.md)
- [iOS Guide](docs/platforms/ios/README.md)
- [Windows Guide](docs/platforms/windows/README.md)
- [Linux Guide](docs/platforms/linux/README.md)
- [macOS Guide](docs/platforms/macos/README.md)

Recommended reading order:
1. Start from this README for the global API and cross-platform overview.
2. Open the guide for each target platform you ship.
3. Keep per-platform setup isolated in your app repository
   (entitlements, extension targets, signing) to avoid cross-platform mixups.

## Project Structure

- `lib/dart_v2ray.dart`: public export surface.
- `lib/src/core`: high-level client, validation, status control, bug report.
- `lib/src/platform`: platform interface and method-channel implementation.
- `lib/src/models`: public data models.
- `lib/src/share_links`: share-link parsing and config generation.
- `lib/url`: backward-compatible exports for share-link types.

## Development

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

## License

MIT
