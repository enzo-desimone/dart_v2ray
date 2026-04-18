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

`requireTun: false` is the recommended default rollout for macOS desktop
builds (proxy-only mode).

To force full-tunnel routing on macOS, set `requireTun: true`.
When enabled, the desktop core injects TUN inbound/routing config and fails
fast if a TUN config cannot be constructed from the provided JSON.

## Notes

- macOS support is implemented through the shared desktop native core.
- `onStatusChanged` emits the same payload contract used by desktop targets.
- Windows-only diagnostics methods remain callable and return
  `{"supported":"false","reason":"windows_only"}` on macOS.
- Full-tunnel TUN behavior depends on macOS runtime permissions/signing model of
  your app distribution.

## Troubleshooting

- `initialize` / `start` fails:
  - Ensure the binary exists and is executable (`chmod +x macos/bin/xray`).
  - Verify discovery from terminal (`which xray`) or set
    `XRAY_EXECUTABLE=/absolute/path/to/xray`.
- No traffic observed: check `onStatusChanged` fields (`state`,
  `connectionPhase`, `isProcessRunning`) and confirm config validity.

## Compatibility Note

The high-level Dart API is platform-agnostic, so app-layer Dart code usually
requires minimal changes when enabling macOS.
