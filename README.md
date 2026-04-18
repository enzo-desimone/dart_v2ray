# dart_v2ray

`dart_v2ray` is a Flutter plugin to manage Xray/V2Ray connections from Dart.
It supports proxy/VPN workflows, runtime status streaming, auto-disconnect, and
share-link parsing (`vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`).

## Platform Status

| Platform | Plugin implementation | Notes |
| --- | --- | --- |
| Android | Available | Production-ready; tested by project team |
| iOS | Available | Requires Packet Tunnel setup and XCFramework source |
| Windows | Available | Production-ready; tested by project team |
| Linux | Available | Desktop support via shared native core (not yet fully team-validated) |
| macOS | Available | Proxy mode via desktop core; full-tunnel via Packet Tunnel setup |

## Installation

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

`requireTun: true` requires full-device/system TUN mode.
`requireTun: false` runs proxy-only mode.

## Core API

Main class:
- `DartV2ray`

Connection lifecycle:
- `initialize(...)`
- `requestPermission()`
- `start(...)`
- `stop()`

Diagnostics and utilities:
- `getServerDelay(...)`
- `getConnectedServerDelay(...)`
- `getCoreVersion()`
- `configureWindowsDebugLogging(...)`
- `getWindowsTrafficDiagnostics()`
- `getWindowsDebugLogs(...)`
- `buildWindowsBugReport(...)`

Auto-disconnect:
- `updateAutoDisconnectTime(...)`
- `getRemainingAutoDisconnectTime()`
- `cancelAutoDisconnect()`
- `wasAutoDisconnected()`
- `clearAutoDisconnectFlag()`
- `getAutoDisconnectTimestamp()`

Status streaming:
- `onStatusChanged`
- `startPersistentStatusListener()`
- `persistentStatusStream`
- `latestStatus`
- `stopPersistentStatusListener()`
- `dispose()`

Models:
- `ConnectionStatus`
- `AutoDisconnectConfig`
- `AutoDisconnectExpireBehavior`
- `AutoDisconnectTimeFormat`

Share-link parsers:
- `V2rayUrl`
- `VlessUrl`
- `VmessUrl`
- `TrojanUrl`
- `ShadowsocksUrl`
- `SocksUrl`

## Share-Link Parsing

```dart
final V2rayUrl parsed = DartV2ray.parseShareLink(link);
final String configJson = parsed.getFullConfiguration();
```

## Project Structure

The Dart layer is now organized by responsibility:

- `lib/dart_v2ray.dart`: single public export surface.
- `lib/src/core`: high-level client logic, validation, status manager, bug report builder.
- `lib/src/platform`: platform interface + method-channel implementation.
- `lib/src/models`: public data models.
- `lib/src/share_links`: share-link parsing and config generation.
- `lib/url`: backward-compatible exports to the new share-link paths.

## Platform Guides

Detailed per-platform setup lives in:

- [Documentation Index](docs/README.md)
- [Android Guide](docs/platforms/android/README.md)
- [iOS Guide](docs/platforms/ios/README.md)
- [Windows Guide](docs/platforms/windows/README.md)
- [Linux Guide](docs/platforms/linux/README.md)
- [macOS Guide](docs/platforms/macos/README.md)

## Development

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

## License

MIT
