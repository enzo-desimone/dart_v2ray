# AGENTS.md — dart_v2ray

This file contains project-specific context for AI coding agents. If you are reading this, you are expected to know nothing about the project beyond what is written here and in the source files.

---

## Project Overview

`dart_v2ray` is a **Flutter plugin** that manages Xray/V2Ray VPN and proxy connections from Dart. It supports:

- **Android** (Kotlin + bundled native binaries)
- **iOS** (Swift + Packet Tunnel Network Extension + auto-downloaded `XRay.xcframework`)
- **Windows** (C++ + shared desktop core + auto-downloaded `Xray-windows-64.zip` at CMake configure time)
- **Linux** (C++ + shared desktop core)
- **macOS** (Obj-C++/Swift + Go `c-archive` bridge linked in-process)

The plugin exposes a single high-level Dart API (`DartV2ray`) with methods for:
- Connection lifecycle: `initialize`, `requestPermission`, `start`, `stop`
- Diagnostics: `getServerDelay`, `getConnectedServerDelay`, `getCoreVersion`
- Windows-specific debugging: `configureWindowsDebugLogging`, `getDesktopDebugLogs`, `buildWindowsBugReport`
- Auto-disconnect timer controls
- Real-time status streaming (`onStatusChanged`, `persistentStatusStream`)
- Share-link parsing for `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`

Homepage: https://github.com/enzo-desimone/dart_v2ray  
License: MIT

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Dart public API | Flutter 3.3+, Dart SDK ^3.7.2 |
| Android native | Kotlin 1.9.10, Gradle 8.1, AGP 8.1, compileSdk 34, minSdk 23 |
| iOS native | Swift 5.0, CocoaPods, `XRay.xcframework` (auto-downloaded) |
| Windows native | C++17, CMake 3.14+, Flutter Windows plugin API |
| Linux native | C++17, CMake 3.14+, Flutter Linux plugin API |
| macOS native | Objective-C++, CocoaPods, Go 1.23.6 bridge (`c-archive`) |
| Shared desktop core | C++ (`shared/desktop_v2ray_core.cc/h`) used by Windows and Linux |

Key dependencies:
- `plugin_platform_interface: ^2.1.8`
- `flutter_lints: ^6.0.0` (dev)
- Android: `gson:2.10.1`, `appcompat:1.6.1`
- macOS Go bridge: `github.com/xtls/xray-core v26.4.17`

---

## Project Structure

```
lib/
  dart_v2ray.dart                          # Public export surface
  dart_v2ray_method_channel.dart           # Backward-compatible shim
  dart_v2ray_platform_interface.dart       # Backward-compatible shim
  src/
    core/
      dart_v2ray_client.dart               # Main DartV2ray class (public API)
      config_validator.dart                # Xray JSON validation before native calls
      status/
        persistent_status_controller.dart  # Survives UI resubscriptions
        windows_status_fallback_mapper.dart# Fallback when event stream stalls
      windows/
        windows_bug_report_builder.dart    # Assembles debug payloads for bug reports
    models/
      vpn_status.dart                      # VpnStatus + VpnConnectionState enum
      auto_disconnect_config.dart          # AutoDisconnectConfig + enums
    platform/
      dart_v2ray_platform.dart             # Abstract platform interface
      method_channel_dart_v2ray.dart       # MethodChannel + EventChannel impl
      status_event_parser.dart             # Parses native status list → VpnStatus
    share_links/
      v2ray_url.dart                       # Base parser + JSON generator
      vless_url.dart, vmess_url.dart,
      trojan_url.dart, shadowsocks_url.dart,
      socks_url.dart                       # Concrete share-link parsers
      share_links.dart                     # Barrel export
  url/                                     # Backward-compatible re-exports

android/
  build.gradle.kts
  src/main/kotlin/com/dart/v2ray/vpn/
    DartV2rayPlugin.kt                     # Android MethodChannel handler
    service/V2RayVpnService.kt
    xray/core/XrayCoreManager.kt
    xray/dto/XrayConfig.kt
    xray/service/XrayVPNService.kt
    xray/utils/AppConfigs.kt
    xray/utils/Utilities.kt
  src/test/kotlin/.../DartV2rayPluginTest.kt
  src/main/jniLibs/arm64-v8a/lib{xray,tun2socks}.so
  src/main/jniLibs/armeabi-v7a/lib{xray,tun2socks}.so

ios/
  Classes/DartV2rayPlugin.swift            # iOS MethodChannel handler
  Classes/Helpers/AutoDisconnectHelper.swift
  Classes/Managers/AutoDisconnectNotificationManager.swift
  Classes/Managers/PacketTunnelManager.swift
  dart_v2ray.podspec                       # Auto-downloads XRay.xcframework

windows/
  CMakeLists.txt                           # Auto-downloads Xray-windows-64.zip
  dart_v2ray_plugin.cpp/h
  dart_v2ray_plugin_c_api.cpp

linux/
  CMakeLists.txt
  dart_v2ray_plugin.cc

macos/
  Classes/DartV2rayPlugin.h/mm
  Classes/DesktopV2rayCoreBridge.cc
  ExtensionTemplate/PacketTunnelProvider.swift
  ExtensionTemplate/XrayBridge.swift
  xray_bridge_go/
    bridge.go
    go.mod
    include/libxraybridge.h
    scripts/build_macos_bridge.sh
  dart_v2ray.podspec                       # Links libxraybridge.a
  bin/geoip.dat, bin/geosite.dat

shared/
  desktop_v2ray_core.cc/h                  # Shared C++ core (Windows + Linux)

example/
  lib/main.dart                            # Full-featured example app
  integration_test/plugin_integration_test.dart
  test/widget_test.dart

docs/
  platforms/android/README.md
  platforms/ios/README.md
  platforms/windows/README.md
  platforms/linux/README.md
  platforms/macos/README.md
```

---

## Build and Test Commands

```bash
# Install Dart dependencies
flutter pub get

# Static analysis (uses package:flutter_lints/flutter.yaml)
flutter analyze

# Format Dart code
dart format lib test

# Run Dart/Flutter tests
flutter test

# Run a specific test file
flutter test test/dart_v2ray_test.dart
```

Android unit tests (Kotlin):
```bash
./gradlew :dart_v2ray:test
```

macOS Go bridge build (required before `pod install` on macOS):
```bash
cd macos/xray_bridge_go
./scripts/build_macos_bridge.sh
```

---

## Code Style Guidelines

- **Dart**: Follows `package:flutter_lints/flutter.yaml`. Use `dart format` before committing.
- **Kotlin**: Standard Android Kotlin conventions. `runCatching { }` is preferred for safe native calls.
- **Swift**: Standard Swift conventions. Uses `Task`/`await` for async native work.
- **C++**: C++17. Uses `std::optional`, `std::chrono`, and RAII patterns. Platform-specific code is guarded with `#if defined(_WIN32)`.
- **Comments**: Use `///` for Dart doc comments. Use `// MARK: -` sections in Swift/Kotlin where applicable.
- **Imports**: Group Flutter/SDK imports first, then package imports, then relative imports.

---

## Testing Instructions

### Dart/Flutter tests
- Run `flutter test` from the plugin root.
- There is an integration test in `example/integration_test/plugin_integration_test.dart` that verifies share-link parsing.
- The example app in `example/lib/main.dart` is the primary manual/integration testing surface.

### Android unit tests
- Located in `android/src/test/kotlin/com/dart/v2ray/vpn/DartV2rayPluginTest.kt`
- Uses JUnit 4.13.2 and Mockito 5.0.0
- Run via Gradle: `./gradlew :dart_v2ray:test`

### Native/desktop testing
- Windows: the example app must run as Administrator for TUN workflows.
- macOS: the Go bridge must be built first (`build_macos_bridge.sh`).
- Linux: ensure Xray runtime binaries are reachable in the deployment environment.

---

## Key Architecture Patterns

### Platform Interface Pattern
The plugin uses the standard Flutter platform-interface pattern:

```
DartV2ray (public API)
  → DartV2rayPlatform (abstract interface)
    → MethodChannelDartV2ray (method/event channels)
      → Native implementations per platform
```

### Status Streaming
- Native side emits status events as a **list of 12 positional fields** over `EventChannel("dart_v2ray/status")`.
- `StatusEventParser` converts this list into `VpnStatus`.
- `PersistentStatusController` keeps the latest snapshot alive even when no UI widget is listening.
- On Windows, if the native event stream stalls for >6 seconds, a fallback poll of `getWindowsTrafficDiagnostics()` runs every 3 seconds.

### Share-Link Parsing
- All parsers extend `V2rayUrl` in `lib/src/share_links/v2ray_url.dart`.
- The base class generates a full Xray JSON configuration with `inbounds`, `outbounds`, `dns`, `routing`, and `streamSettings`.
- Subclasses only implement protocol-specific parsing (e.g., `VlessUrl`, `VmessUrl`).

---

## Security Considerations

- **Android**: Requires `VpnService` permission. Notification permission is requested on Android 13+ (`POST_NOTIFICATIONS`).
- **iOS/macOS**: Requires a Packet Tunnel Network Extension target, shared App Group, and matching provisioning profile entitlements.
- **Windows**: TUN/VPN workflows require the app to run with **Administrator privileges**. The CMake build auto-downloads and verifies `Xray-windows-64.zip` via SHA256 (from `.dgst` or an explicit hash).
- **iOS Framework Download**: The podspec auto-downloads `XRay.xcframework.zip` from a hosted URL and verifies it with SHA256. This can be overridden via environment variables (`DART_V2RAY_IOS_FRAMEWORK_*`).
- **Config Validation**: Before any native `start` call, `validateXrayConfig()` checks that the config is valid JSON and contains at least one non-empty `outbounds` entry.
- **macOS Bridge**: Uses a statically linked Go `c-archive` bridge (`libxraybridge.a`) so no external `xray` executable is spawned. This is App-Store-friendly.

---

## Platform-Specific Build Notes

| Platform | Runtime Source | Override Mechanism |
|----------|---------------|-------------------|
| Android | Bundled `libxray.so` + `libtun2socks.so` in `jniLibs/` | N/A |
| iOS | Auto-downloaded `XRay.xcframework` at `pod install` | `DART_V2RAY_IOS_FRAMEWORK_ZIP_PATH`, `DART_V2RAY_IOS_FRAMEWORK_URL`, `DART_V2RAY_IOS_FRAMEWORK_SHA256` |
| Windows | Auto-downloaded `Xray-windows-64.zip` at CMake configure | `DART_V2RAY_WINDOWS_XRAY_ZIP_PATH`, `DART_V2RAY_WINDOWS_XRAY_ZIP_URL`, `DART_V2RAY_WINDOWS_XRAY_DGST_URL`, `DART_V2RAY_WINDOWS_XRAY_ZIP_SHA256`, `DART_V2RAY_XRAY_VERSION` |
| Linux | Must be provided by deployment environment | N/A |
| macOS | Built Go bridge (`libxraybridge.a`) + committed `geoip.dat`/`geosite.dat` | N/A |

---

## Important Files for Agents

- `pubspec.yaml` — Flutter plugin manifest and platform registration.
- `analysis_options.yaml` — Lint rules (`include: package:flutter_lints/flutter.yaml`).
- `lib/src/core/dart_v2ray_client.dart` — The public `DartV2ray` class. Most feature changes touch this or the platform interface.
- `lib/src/platform/dart_v2ray_platform.dart` — Abstract platform contract. Adding a new method requires updating this file and all native implementations.
- `lib/src/platform/method_channel_dart_v2ray.dart` — MethodChannel wire format. Method names here must match native side exactly.
- `lib/src/models/vpn_status.dart` — Canonical status model and `VpnConnectionState` enum.
- `shared/desktop_v2ray_core.h/cc` — Shared C++ core for Windows and Linux. macOS uses its own Go bridge.
- `CLAUDE.md` — Additional macOS/iOS native setup details, Xcode build phases, and troubleshooting matrix.
