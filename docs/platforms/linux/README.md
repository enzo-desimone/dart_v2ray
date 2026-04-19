# Linux Guide

This guide covers Linux-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: implementation present; not yet fully validated by project team

## Requirements

- Flutter desktop app with Linux enabled.
- Runtime access to required Xray binaries/libraries used by your deployment.

## Usage

Linux uses the same high-level API as other platforms:

```dart
await v2ray.initialize();
await v2ray.start(
  remark: 'Linux profile',
  config: configJson,
  requireTun: false,
);
```

## Runtime Configuration

- `requireTun: false`: proxy-only mode (default).
- `requireTun: true`: requests TUN routing through the native core. Depending
  on your distro/environment, this may require extra privileges/capabilities.

## Notes

- Linux support is implemented through the shared desktop native core.
- Behavior depends on local desktop networking and permissions model.
- If your app package format isolates files (Snap/Flatpak/AppImage), ensure the
  required binaries are reachable at runtime.

## Troubleshooting

- Start failures: verify binary availability and execution permissions.
- No traffic counters: inspect `onStatusChanged` and confirm process lifecycle.
