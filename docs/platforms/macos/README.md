# macOS Guide

This guide covers macOS-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: implementation present; validate in your target
  signing/distribution setup

## Requirements

- Flutter desktop app with macOS enabled.
- No manual runtime download is required for default proxy mode.
  During `pod install`, the plugin downloads Xray runtime files and bundles:
  - `xray`
  - `geoip.dat`
  - `geosite.dat`
- For full-tunnel (`requireTun: true`), complete the native setup below.

## Runtime Source Overrides (Optional)

If your CI/build is offline or you need a pinned mirror, configure:

- `DART_V2RAY_XRAY_VERSION`:
  release tag used by default URLs.
- `DART_V2RAY_MACOS_XRAY_ARM64_ZIP_PATH` /
  `DART_V2RAY_MACOS_XRAY_AMD64_ZIP_PATH`:
  local zip archives.
- `DART_V2RAY_MACOS_XRAY_ARM64_URL` /
  `DART_V2RAY_MACOS_XRAY_AMD64_URL`:
  custom hosted URLs.
- `DART_V2RAY_MACOS_XRAY_ARM64_SHA256` /
  `DART_V2RAY_MACOS_XRAY_AMD64_SHA256`:
  explicit checksum pins.

## Required Native Setup (`requireTun: true`)

macOS full-tunnel mode uses a Packet Tunnel extension and `Tun2SocksKit`.

1. Add a Packet Tunnel Network Extension target (for example `XrayTunnel`).
2. Set extension bundle id to `<providerBundleIdentifier>.XrayTunnel`.
3. Configure the same App Group in both app and extension entitlements.
4. Pass matching identifiers in Dart:

```dart
await v2ray.initialize(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

5. Add Swift package `Tun2SocksKit` and link product `Tun2SocksKit` to the
   extension target.
6. Ensure the extension has Xray runtime files as resources:
   `xray`, `geoip.dat`, `geosite.dat`.
   The plugin bundles these files for the app runtime, but extension targets
   still need their own resource copy in `Copy Bundle Resources`.

The native core resolves `xray` in this order:
1. `XRAY_EXECUTABLE` environment variable.
2. Bundled/runtime candidates:
   - `<runtime>/xray`
   - `<runtime>/bin/xray`
   - `<runtime>/macos/bin/xray`
   - `<App>.app/Contents/Resources/xray`
   - `<App>.app/Contents/Resources/bin/xray`
   - `<App>.app/Contents/Resources/macos/bin/xray`
3. `xray` from `PATH`.

Important:
- macOS does not require `XRay.xcframework` (that is an iOS flow).
- Avoid linking Flutter/plugin frameworks to the extension target.
  Keep extension linker settings isolated from Runner target.

## Usage

macOS uses the same high-level API as Linux/Windows:

```dart
await v2ray.initialize();
await v2ray.start(
  remark: 'macOS profile',
  config: configJson,
  requireTun: false,
);
```

`requireTun: false` runs proxy-only mode through desktop core.

`requireTun: true` uses Packet Tunnel mode (NetworkExtension), aligned with iOS
flow, and requires the native setup above.

Example for `requireTun: true`:

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

## Notes

- macOS support uses two paths:
  - `requireTun: false`: shared desktop native core.
  - `requireTun: true`: Packet Tunnel (`NETunnelProviderManager`).
- `onStatusChanged` emits the same payload contract used by desktop targets.
- Windows-only diagnostics methods remain callable and return
  `{"supported":"false","reason":"windows_only"}` on macOS.
- Full-tunnel behavior depends on your macOS signing/entitlements distribution
  setup for Network Extension + App Group.

## Troubleshooting

- `initialize` / `start` fails:
  - Ensure `pod install` completed and downloaded runtime files.
  - Ensure the binary exists and is executable.
  - Verify discovery from terminal (`which xray`) or set
    `XRAY_EXECUTABLE=/absolute/path/to/xray`.
- `requireTun: true` fails:
  - Verify Packet Tunnel target exists and is signed.
  - Verify extension bundle id is `<providerBundleIdentifier>.XrayTunnel`.
  - Verify App Group string matches exactly across app + extension.
- Build fails with Flutter symbols in extension (for example
  `_FlutterMethodNotImplemented`, `FlutterMethodChannel`):
  - Extension target is incorrectly linking Runner/Flutter plugin frameworks.
  - Remove inherited Runner linker flags from extension target.
- Tunnel connects but no traffic:
  - Verify extension bundle contains `xray`, `geoip.dat`, `geosite.dat`.
  - Verify your Xray JSON has at least one inbound `socks`/`http`/`mixed`
    with a valid `port` (used by tun2socks).
- No traffic observed: check `onStatusChanged` fields (`state`,
  `connectionPhase`, `isProcessRunning`) and confirm config validity.

## Compatibility Note

The high-level Dart API is platform-agnostic, so app-layer Dart code usually
requires minimal changes when enabling macOS.
