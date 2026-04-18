# macOS Guide

This guide covers macOS-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: implementation present; validate in your target
  signing/distribution setup

## Requirements

- Flutter desktop app with macOS enabled.
- Runtime access to the Xray executable.
  Put your binary in `macos/bin/xray` inside this plugin package: CocoaPods
  bundles `macos/bin/xray*` into app resources automatically.
  The native core resolves it in this order:
  1. `XRAY_EXECUTABLE` env var
  2. Bundled candidates near the app/runtime:
     - `<runtime>/xray`
     - `<runtime>/bin/xray`
     - `<runtime>/macos/bin/xray`
     - `<App>.app/Contents/Resources/xray`
     - `<App>.app/Contents/Resources/bin/xray`
     - `<App>.app/Contents/Resources/macos/bin/xray`
  3. `xray` from `PATH`
- For `requireTun: true`:
  1. Add a Packet Tunnel Network Extension target to the macOS app.
  2. Configure a shared App Group for app + extension.
  3. Ensure extension bundle id is `<providerBundleIdentifier>.XrayTunnel`.
  4. Pass matching `providerBundleIdentifier` and `groupIdentifier` to
     `initialize(...)`.

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
  - Ensure the binary exists and is executable (`chmod +x macos/bin/xray`).
  - Verify discovery from terminal (`which xray`) or set
    `XRAY_EXECUTABLE=/absolute/path/to/xray`.
- `requireTun: true` fails:
  - Verify Packet Tunnel target exists and is signed.
  - Verify extension bundle id is `<providerBundleIdentifier>.XrayTunnel`.
  - Verify App Group string matches exactly across app + extension.
- No traffic observed: check `onStatusChanged` fields (`state`,
  `connectionPhase`, `isProcessRunning`) and confirm config validity.

## Compatibility Note

The high-level Dart API is platform-agnostic, so app-layer Dart code usually
requires minimal changes when enabling macOS.
