# macOS Guide

This guide covers macOS-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: implementation present; validate in your target
  signing/distribution setup

## Requirements

- Flutter desktop app with macOS enabled.
- Runtime access to the Xray executable.
  The native core resolves it in this order:
  1. `XRAY_EXECUTABLE` env var
  2. `xray` from `PATH`

## Usage

macOS uses the same high-level API as Linux/Windows:

```dart
await v2ray.initialize();
await v2ray.start(
  remark: 'macOS profile',
  config: configJson,
  proxyOnly: true,
);
```

`proxyOnly: true` is the recommended default rollout for macOS desktop builds.

## Notes

- macOS support is implemented through the shared desktop native core.
- `onStatusChanged` emits the same payload contract used by desktop targets.
- Windows-only diagnostics methods remain callable and return
  `{"supported":"false","reason":"windows_only"}` on macOS.

## Troubleshooting

- `initialize` / `start` fails: verify Xray is reachable (`which xray`) or set
  `XRAY_EXECUTABLE=/absolute/path/to/xray`.
- No traffic observed: check `onStatusChanged` fields (`state`,
  `connectionPhase`, `isProcessRunning`) and confirm config validity.

## Compatibility Note

The high-level Dart API is platform-agnostic, so app-layer Dart code usually
requires minimal changes when enabling macOS.
