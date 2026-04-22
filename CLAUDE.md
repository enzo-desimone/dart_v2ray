# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## macOS runtime files

The plugin is self-contained on macOS. The three Xray runtime files must be committed directly into `macos/bin/` inside the plugin:

- `macos/bin/xray` — Xray core executable (must be executable)
- `macos/bin/geoip.dat` — Xray geo IP database
- `macos/bin/geosite.dat` — Xray geo site database

These files are tracked by git (not in `.gitignore`). The `prepare_command` in the podspec only verifies they exist and sets `chmod +x` on `xray` — it never downloads or copies from external sources. No `DART_V2RAY_MACOS_RUNTIME_DIR` or host-app `macos/bin/` dependency.

At runtime the C++ `DiscoverRuntimePaths()` finds `xray` via `_NSGetExecutablePath`: it searches `YourApp.app/Contents/MacOS/` → `../Resources/` and parent directories. CocoaPods copies the files from `bin/` to the app bundle's `Contents/Resources/` via `s.resources`.

## Commands

```bash
flutter pub get          # Install dependencies
flutter analyze          # Static analysis (flutter_lints)
dart format lib test     # Format code
flutter test             # Run all tests
flutter test test/dart_v2ray_test.dart  # Run a single test file
```

## Architecture

**dart_v2ray** is a Flutter plugin that manages Xray/V2Ray VPN/proxy connections across Android, iOS, macOS, Linux, and Windows by bridging Dart to native Xray core binaries.

### Layered Structure

```
DartV2ray (Public API)  →  DartV2rayPlatform (Abstract)  →  MethodChannelDartV2ray (Channels)  →  Native
```

- **`lib/src/core/dart_v2ray_client.dart`** — The `DartV2ray` class; single entry point for all operations: `initialize`, `start`, `stop`, `requestPermission`, auto-disconnect controls, diagnostics, and share-link parsing dispatch.
- **`lib/src/platform/dart_v2ray_platform.dart`** — Abstract platform interface using the Flutter platform-interface pattern.
- **`lib/src/platform/method_channel_dart_v2ray.dart`** — Binds to `MethodChannel("dart_v2ray")` for commands and `EventChannel("dart_v2ray/status")` for the real-time status stream.
- **`lib/src/platform/status_event_parser.dart`** — Converts the native status list (12 positional fields) into a `VpnStatus` object.

### Share-Link Parsers

`lib/src/share_links/` contains one class per protocol: VLESS, VMess, Trojan, Shadowsocks, SOCKS. All extend `V2rayUrl` (the base class in `v2ray_url.dart`), which provides the full Xray JSON generation via `getFullConfiguration()`. Subclasses only implement protocol-specific parsing and `populateTransportSettings()` / `populateTlsSettings()`.

### Status System

- **`PersistentStatusController`** — Maintains the latest `VpnStatus` snapshot and bridges `onStatusChanged` / `persistentStatusStream` so UI resubscriptions don't lose state.
- **Windows fallback** — If the native event stream stalls (>6 s), `PersistentStatusController` polls `getWindowsTrafficDiagnostics()` every 3 s and converts the result via `WindowsStatusFallbackMapper`.

### Key Models

- **`VpnStatus`** — Connection snapshot: `connectionState` (`VpnConnectionState` enum with 5 values), traffic upload/download speeds + totals, session duration, auto-disconnect remaining, transport mode, phase, status reason.
- **`AutoDisconnectConfig`** — Duration-based auto-disconnect passed into `start()`.

### Config Validation

`ConfigValidator` (in `lib/src/core/config_validator.dart`) validates that the Xray JSON string is well-formed and contains at least one non-empty `outbounds` entry before any native call is made.

### Backward-Compatibility Exports

`lib/dart_v2ray_method_channel.dart`, `lib/dart_v2ray_platform_interface.dart`, and `lib/url/*.dart` are re-export shims for older import paths — do not add logic there.
