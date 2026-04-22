# macOS Guide

This guide covers macOS-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: implementation present; validate in your target
  signing/distribution setup

---

## Runtime Files — Self-Contained Plugin

The plugin is **self-contained** on macOS. The three Xray runtime files are committed
directly inside the plugin at:

```
macos/bin/
  xray          ← universal binary (arm64 + x86_64), executable bit set
  geoip.dat     ← architecture-independent
  geosite.dat   ← architecture-independent
```

No host-app `macos/bin/` directory is required. No `DART_V2RAY_MACOS_RUNTIME_DIR`
environment variable is needed. No download step runs during `pod install`.

The `prepare_command` in `dart_v2ray.podspec`:
1. Verifies all three files exist at `$(pwd)/bin/` — always the plugin's own
   `macos/bin/`, regardless of the host project location.
2. Runs `chmod +x` on `xray`.
3. Fails immediately with a clear error if any file is missing.

CocoaPods copies them to the host app's `Contents/Resources/` via
`s.resources = ['bin/xray', 'bin/geoip.dat', 'bin/geosite.dat']`.

### Universal binary

The `xray` binary supports both Apple Silicon and Intel in a single file:

```bash
lipo -create xray-arm64 xray-x86_64 -output macos/bin/xray
lipo -info macos/bin/xray   # verify: arm64 x86_64
```

`geoip.dat` and `geosite.dat` are architecture-independent and require no merging.

### Committing the runtime to git

```bash
chmod +x macos/bin/xray
git update-index --chmod=+x macos/bin/xray
git add macos/bin/xray macos/bin/geoip.dat macos/bin/geosite.dat
git commit -m "feat(macos): bundle xray runtime inside plugin"
```

`git update-index --chmod=+x` preserves the executable bit in the repository,
regardless of the platform on which the repo is cloned.

### Runtime path discovery

`DiscoverRuntimePaths()` in `shared/desktop_v2ray_core.cc` resolves `xray` at
runtime using this order:

1. `XRAY_EXECUTABLE` environment variable (override only).
2. `_NSGetExecutablePath` → searches `YourApp.app/Contents/MacOS/`,
   then `../Resources/`, then up to 8 parent directories.
   Each directory is probed for `<root>/xray`, `<root>/bin/xray`,
   `<root>/macos/bin/xray`.
3. `xray` from `$PATH` as final fallback.

CocoaPods places resources at `Contents/Resources/`, which is found at step 2.

---

## Usage

macOS uses the same high-level Dart API as Linux/Windows.

### Proxy mode (`requireTun: false`)

```dart
await v2ray.initialize();
await v2ray.start(
  remark: 'macOS profile',
  config: configJson,
  requireTun: false,
);
```

Xray runs as a local process with a socks/http/mixed inbound. No system routing
is modified.

### VPN / full-tunnel mode (`requireTun: true`)

```dart
await v2ray.initialize(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);

await v2ray.start(
  remark: 'macOS full tunnel',
  config: configJson,
  requireTun: true,
);
```

Uses `NETunnelProviderManager` / Packet Tunnel. Requires the native setup below.

---

## Native Setup — `XrayTunnel` Extension (`requireTun: true`)

### 1. Add the Packet Tunnel target

1. In Xcode add a **Network Extension** target named `XrayTunnel`.
2. Set its bundle identifier to `<providerBundleIdentifier>.XrayTunnel`
   (the plugin appends `.XrayTunnel` automatically if the suffix is absent).
3. Add the `Network Extensions` and `App Groups` capabilities to both
   `Runner` and `XrayTunnel`. Use the same App Group string in both.

### 2. Link Tun2SocksKit

Add the Swift package `Tun2SocksKit` and link the `Tun2SocksKit` product to the
`XrayTunnel` target only — not to `Runner`.

### 3. Copy runtime files into the extension bundle

CocoaPods `s.resources` delivers files to the main app bundle only. The extension
runs in a separate sandbox and needs its own copies. Add a **Run Script** build
phase to the `XrayTunnel` target:

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

This mirrors how Android's Gradle build copies native binaries automatically.
The source path uses Flutter's ephemeral symlink, which always resolves to the
correct version of the plugin for the current project.

**Required setting — disable script sandboxing:**

| Target | Setting | Value |
|---|---|---|
| `XrayTunnel` | `ENABLE_USER_SCRIPT_SANDBOXING` | `No` |

In Xcode UI: **Build Settings → User Script Sandboxing → No**.
Without this, the Run Script cannot write to `TARGET_BUILD_DIR` and the build fails silently.

### 4. Xcode — `XrayTunnel` target configuration

**General / Frameworks and Libraries:**

| Framework | Embed |
|---|---|
| `NetworkExtension.framework` | Do Not Embed |
| `Pods_XrayTunnel.framework` | Do Not Embed |

Extensions must not embed frameworks already linked by the host app.
Remove any `Embed Frameworks` phase in `XrayTunnel`, or leave it empty.

**Build Phases:**

| Phase | Notes |
|---|---|
| Run Script (runtime copy) | Script above; copies `xray`, `geoip.dat`, `geosite.dat` |
| Copy Bundle Resources | May remain empty — the Run Script handles delivery |

### 5. Xcode — `Runner` target configuration

**General / Frameworks, Libraries, and Embedded Content:**

| Item | Embed |
|---|---|
| `XrayTunnel.appex` | Embed Without Signing |
| `Pods_Runner.framework` | Do Not Embed |

**Build Phases — required order:**

Placing `Embed Foundation Extensions` before `[CP] Embed Pods Frameworks` causes
dependency cycle errors. Correct order:

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

### 6. Version consistency

`CFBundleShortVersionString` of `XrayTunnel` must match `Runner`:

```
Runner:      CFBundleShortVersionString = 1.0.0
XrayTunnel:  CFBundleShortVersionString = 1.0.0
```

Mismatches produce App Store and archive warnings.

### 7. Entitlements

`XrayTunnel.entitlements` must include the App Group capability and, if the
extension makes direct outbound network connections, the network client entitlement:

```xml
<key>com.apple.security.application-groups</key>
<array>
  <string>group.com.example.myapp</string>
</array>
<key>com.apple.security.network.client</key>
<true/>
```

Align with the provisioning profile configured in Xcode Signing & Capabilities.

---

## `providerConfiguration` contract

When `requireTun: true` starts on macOS, the plugin writes these keys to
`NETunnelProviderProtocol.providerConfiguration`:

| Key | Type | Description |
|---|---|---|
| `xrayConfig` | `Data` | Full Xray JSON config |
| `dnsServers` | `[String]` | DNS servers from Dart `dns_servers` |
| `bypassSubnets` | `[String]` | Bypass CIDRs from Dart `bypass_subnets` |
| `excludedRemoteHosts` | `[String]` | Host/address candidates parsed from Xray outbounds |
| `groupIdentifier` | `String` | App Group identifier |
| `remark` | `String` (optional) | Profile name |
| `autoDisconnect` | `Dictionary` (optional) | Auto-disconnect options |
| `tunDriver` | `String` | Currently `xray_fd` |
| `tunFdEnvironmentKey` | `String` | Currently `XRAY_TUN_FD` |
| `requireTun` | `Bool` | Always `true` in Packet Tunnel mode |

Treat unknown keys as optional for forward compatibility.

---

## Post-Build Verification

After a Debug build, verify that the extension resources were copied correctly:

```bash
ls -lh build/macos/Build/Products/Debug/\
YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/
# Expected: xray (executable), geoip.dat, geosite.dat

file build/.../XrayTunnel.appex/Contents/Resources/xray
# Expected: Mach-O universal binary with 2 architectures: [x86_64] [arm64]
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `dart_v2ray(macOS): runtime files missing from the plugin` | `macos/bin/` files absent or excluded by `.gitignore` | Commit files; verify `.gitignore` no longer excludes them |
| `Bundled xray executable not found in extension resources` | Run Script did not copy files into `.appex` | Check `ENABLE_USER_SCRIPT_SANDBOXING = No`; verify `SRCROOT` path in script |
| `Xray process terminated with status: 255` | `xray` binary crashed immediately | Verify `lipo -info macos/bin/xray` shows both architectures; check executable bit |
| Sandbox / network access errors in extension | Missing entitlements | Add `com.apple.security.network.client` to `XrayTunnel.entitlements` |
| Build cycle / archive error on `Runner` | `Embed Foundation Extensions` before CocoaPods phase | Reorder Build Phases per the table above |
| Flutter symbols in extension linker errors | Extension links Flutter/plugin frameworks | Set `Pods_XrayTunnel.framework` to Do Not Embed |
| Tunnel connects but no traffic | Xray JSON config missing valid inbound or geodata | Verify `geoip.dat`/`geosite.dat` are in extension resources; check inbound config |
| `initialize` / `start` fails with "xray not found" | `DiscoverRuntimePaths` could not locate binary | Verify `Contents/Resources/xray` exists; as override set `XRAY_EXECUTABLE` |

### Checking runtime discovery

```bash
# In the host app bundle (proxy mode)
ls -l YourApp.app/Contents/Resources/xray

# In the extension bundle (VPN mode)
ls -l YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/xray
```

Use **Console.app** filtering by `XrayTunnel` process name to read extension
runtime logs, including `xray` stdout/stderr.

---

## Notes

- macOS does not use `XRay.xcframework` — that is an iOS-only flow.
- `getDesktopDebugLogs()` is available on macOS and returns plugin-log metadata
  and tail content from a temp log file.
- If your Xray JSON includes `log.access` / `log.error` paths,
  `getDesktopDebugLogs()` also returns those log files' tail content.
- Full-tunnel behavior depends on your macOS signing/entitlements distribution
  setup for Network Extension + App Group.
- `onStatusChanged` emits the same 12-field payload contract used by all desktop targets.

---

## Xray-core TUN Implementation Plan

For implementing full-tunnel (`requireTun: true`) using Xray-core's native TUN FD
primitives and proper routing anti-loop, refer to:

- [`XRAY_CORE_TUN_IMPLEMENTATION_PLAN.md`](./XRAY_CORE_TUN_IMPLEMENTATION_PLAN.md)
