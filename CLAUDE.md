# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get          # Install dependencies
flutter analyze          # Static analysis (flutter_lints)
dart format lib test     # Format code
flutter test             # Run all tests
flutter test test/dart_v2ray_test.dart  # Run a single test file
```

---

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

---

## macOS / iOS: Packaging of Xray Runtime

### Plugin is self-contained

The plugin owns its runtime files. There is no dependency on `./macos/bin/` in the host app, no `DART_V2RAY_MACOS_RUNTIME_DIR` env var, and no download step during `pod install`.

The three runtime files live inside the plugin at:

```
macos/bin/
  xray          ← universal binary (arm64 + x86_64), must be executable
  geoip.dat     ← architecture-independent
  geosite.dat   ← architecture-independent
```

All three are tracked by git (not in `.gitignore`). `geoip.dat` and `geosite.dat` require no merging because they carry no architecture-specific content.

### Universal binary (`xray`)

A single `xray` universal binary is used for macOS, combining both architectures:

```bash
lipo -create xray-arm64 xray-x86_64 -output macos/bin/xray
```

Do not keep separate `xray-arm64` / `xray-x86_64` files in the repo. The universal binary must be committed with its executable bit preserved:

```bash
chmod +x macos/bin/xray
git update-index --chmod=+x macos/bin/xray
```

### podspec `prepare_command`

`macos/dart_v2ray.podspec` uses a `prepare_command` that:

1. Resolves the bin directory as `$(pwd)/bin` — `pwd` during CocoaPods processing is the podspec directory (`macos/`), so this always points to `macos/bin/` inside the plugin, regardless of the host project.
2. Fails immediately with a clear error if any of the three files are absent.
3. Runs `chmod +x` on `xray`.

It never copies files from the host project and never reads any environment variable.

`s.resources = ['bin/xray', 'bin/geoip.dat', 'bin/geosite.dat']` causes CocoaPods to copy those files into the host app's `Contents/Resources/` at build time.

### Runtime path discovery (macOS)

`DiscoverRuntimePaths()` in `shared/desktop_v2ray_core.cc` (macOS branch):

1. Checks `XRAY_EXECUTABLE` env var first (override only).
2. Calls `_NSGetExecutablePath` to find `YourApp.app/Contents/MacOS/`, then walks up to `../Resources/`.
3. Expands the search up to 8 parent directories, probing `root/xray`, `root/bin/xray`, `root/macos/bin/xray` in each.
4. Falls back to `"xray"` on `$PATH`.

CocoaPods-copied resources land at `Contents/Resources/xray`, which is found at step 2.

---

## macOS: Network Extension (`XrayTunnel`)

### Overview

`XrayTunnel` is a `NEPacketTunnelProvider` extension (`.appex`) embedded in the host app. It runs in a separate process with its own sandbox and must carry its own copies of the runtime files — resources from the main app bundle or the plugin are not accessible to the extension at runtime.

The extension looks for `xray`, `geoip.dat`, and `geosite.dat` via `Bundle.main` (i.e., inside `XrayTunnel.appex/Contents/Resources/`).

### Copying runtime files into the extension bundle

Because CocoaPods does not propagate plugin resources into extension targets, a **Run Script** build phase in the `XrayTunnel` Xcode target performs the copy explicitly:

```sh
set -e

PLUGIN_DIR="${SRCROOT}/Flutter/ephemeral/.symlinks/plugins/dart_v2ray"
SOURCE_DIR="${PLUGIN_DIR}/macos/bin"
DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

test -f "${SOURCE_DIR}/xray"        || { echo "error: Missing ${SOURCE_DIR}/xray";        exit 1; }
test -f "${SOURCE_DIR}/geoip.dat"   || { echo "error: Missing ${SOURCE_DIR}/geoip.dat";   exit 1; }
test -f "${SOURCE_DIR}/geosite.dat" || { echo "error: Missing ${SOURCE_DIR}/geosite.dat"; exit 1; }

mkdir -p "${DEST_DIR}"
cp "${SOURCE_DIR}/xray"        "${DEST_DIR}/xray"
cp "${SOURCE_DIR}/geoip.dat"   "${DEST_DIR}/geoip.dat"
cp "${SOURCE_DIR}/geosite.dat" "${DEST_DIR}/geosite.dat"
chmod +x "${DEST_DIR}/xray"
```

This is the same concept as Android's automatic asset/binary copy during Gradle build. The source is the plugin's `macos/bin/` (resolved through Flutter's ephemeral symlink), and the destination is the `.appex` resources folder for the current build configuration.

### Required Xcode setting: disable script sandboxing

For the Run Script to write into `TARGET_BUILD_DIR`, user script sandboxing must be turned off in the `XrayTunnel` target:

| Setting | Value |
|---|---|
| `ENABLE_USER_SCRIPT_SANDBOXING` | `No` |

In Xcode UI: **Build Settings → User Script Sandboxing → No**.

---

## Xcode Configuration

### Target `XrayTunnel` — General / Frameworks

| Framework | Embed |
|---|---|
| `NetworkExtension.framework` | Do Not Embed |
| `Pods_XrayTunnel.framework` | Do Not Embed |

Extensions must not embed dynamic frameworks that the host app already links. An `Embed Frameworks` phase in the extension target should be absent or empty.

### Target `XrayTunnel` — Build Phases

| Phase | Notes |
|---|---|
| Run Script (runtime copy) | Copies `xray`, `geoip.dat`, `geosite.dat` from plugin `macos/bin/` |
| Copy Bundle Resources | May be empty; the Run Script handles resource delivery |

### Target `Runner` — General / Frameworks and Extensions

| Item | Embed |
|---|---|
| `XrayTunnel.appex` | Embed Without Signing |
| `Pods_Runner.framework` | Do Not Embed |

### Target `Runner` — Build Phases (required order)

Dependency cycles occur if `Embed Foundation Extensions` runs before the CocoaPods frameworks phase. The correct order:

1. Target Dependencies
2. Run Build Tool Plug-ins
3. `[CP] Check Pods Manifest.lock`
4. `[CP] Embed Pods Frameworks`
5. `Embed Foundation Extensions`
6. Run Script (any custom scripts)
7. Compile Sources
8. Link Binary With Libraries
9. Copy Bundle Resources
10. `[CP] Copy Pods Resources`

### Version consistency

`CFBundleShortVersionString` of `XrayTunnel` must match the host app (`Runner`). Mismatches produce App Store / archive warnings.

Example: both set to `1.0.0`.

### Entitlements (`XrayTunnel`)

The extension requires entitlements consistent with `NEPacketTunnelProvider` operation. If the extension performs outbound network connections (beyond what the tunnel itself routes), add:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Align entitlements in `XrayTunnel.entitlements` with the provisioning profile and the host app's App Group (used for shared `NSUserDefaults` to store the auto-disconnect timestamp).

---

## Post-Build Verification Checklist

### 1. Runtime files present in the `.appex`

After a Debug build, verify:

```
build/macos/Build/Products/Debug/
  YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/xray
  YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/geoip.dat
  YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/geosite.dat
```

Quick check:

```bash
ls -lh build/macos/Build/Products/Debug/YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/
```

### 2. Executable bit on `xray`

```bash
# In the plugin source
file macos/bin/xray       # should report: Mach-O universal binary with 2 architectures
ls -l macos/bin/xray      # permissions must include x

# In the built appex
ls -l "build/.../XrayTunnel.appex/Contents/Resources/xray"
```

### 3. Log-based diagnosis

Open **Console.app** and filter by the extension process name, or watch the Xcode console during a VPN start attempt.

| Error message | Cause | Fix |
|---|---|---|
| `dart_v2ray(macOS): runtime files missing from the plugin` | `macos/bin/` files absent or ignored by git | Commit files; check `.gitignore` |
| `Bundled xray executable not found in extension resources` | Run Script did not copy files into `.appex` | Check `ENABLE_USER_SCRIPT_SANDBOXING = No`; verify Run Script path |
| `Xray process terminated with status: 255` | `xray` binary crashed immediately | Check architecture match (`lipo -info`); verify executable bit |
| Sandbox errors on network or file access | Entitlements missing or mismatched | Verify `XrayTunnel.entitlements`; check App Group |
| Archive / build cycle errors on `Runner` | `Embed Foundation Extensions` out of order | Reorder Build Phases per the table above |
| `Pods_XrayTunnel.framework` embed error | Framework embedded in extension | Set to Do Not Embed |

---

## Resolved Issues (historical reference)

These issues are fixed. Documented here to avoid re-introducing them.

### macOS plugin

- **`dart_v2ray(macOS): missing runtime files`** — The old podspec copied runtime files from `./macos/bin/` of the host app or from `DART_V2RAY_MACOS_RUNTIME_DIR`. Both were fragile and machine-dependent. Resolved by committing the files into `macos/bin/` inside the plugin itself and simplifying the `prepare_command` to a presence check only.
- **`.gitignore` excluding runtime files** — The files were previously listed in `.gitignore`, preventing them from being tracked. Those entries have been removed.

### Network Extension

- **`Bundled xray executable not found in extension resources`** — CocoaPods `s.resources` delivers files to the main app bundle only, not to embedded extension targets. Resolved by the Run Script in `XrayTunnel` that copies from the plugin's `macos/bin/` at build time.
- **Extension started with empty Resources** — Consequence of the above; now prevented by the presence checks in the Run Script (`exit 1` if any file is missing).

### Xcode build

- **Dependency cycle in `Runner` Build Phases** — `Embed Foundation Extensions` placed before `[CP] Embed Pods Frameworks` caused circular dependency warnings/errors. Resolved by reordering phases.
- **Framework embedding in extension** — `Pods_XrayTunnel.framework` or `NetworkExtension.framework` set to `Embed & Sign` inside the extension caused signing and packaging failures. Both must be `Do Not Embed`.
- **User Script Sandboxing** — With sandboxing enabled (Xcode default since Xcode 14), the Run Script cannot write to `TARGET_BUILD_DIR`. Must be disabled on the `XrayTunnel` target.
