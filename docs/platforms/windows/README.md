# Windows Guide

This guide covers Windows-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: tested and working

## Requirements

- Run app with Administrator privileges for VPN/TUN workflows.
- No manual runtime download is required by default.
  The plugin automatically downloads `Xray-windows-64.zip` at CMake configure
  time, verifies SHA256 (from `.dgst` when available), and bundles:
  - `xray.exe`
  - `wintun.dll`
  - `geoip.dat`
  - `geosite.dat`

## Runtime Source Overrides (Optional)

If your CI/build is offline or you need a pinned mirror, configure one of these:

- `DART_V2RAY_WINDOWS_XRAY_ZIP_PATH`:
  local path to `Xray-windows-64.zip`.
- `DART_V2RAY_WINDOWS_XRAY_ZIP_URL`:
  custom hosted zip URL.
- `DART_V2RAY_WINDOWS_XRAY_DGST_URL`:
  custom `.dgst` URL.
- `DART_V2RAY_WINDOWS_XRAY_ZIP_SHA256`:
  explicit SHA256 (overrides `.dgst` lookup).
- `DART_V2RAY_XRAY_VERSION`:
  release tag used by the default URL.

You can set these as environment variables or CMake cache variables.

## Runtime Configuration

Start call:

```dart
await v2ray.start(
  remark: 'Windows profile',
  config: configJson,
  requireTun: true,
);
```

- `requireTun: true` forces TUN mode.
- `requireTun: false` keeps proxy-only operation (no Wintun required).

## Logging and Diagnostics

Enable logs from Dart:

```dart
await v2ray.configureWindowsDebugLogging(
  enableFileLog: true,
  enableVerboseLog: true,
  captureXrayIo: true,
  clearExistingLogs: true,
);
```

Equivalent environment variables:

- `DART_V2RAY_WINDOWS_FILE_LOG=1`
- `DART_V2RAY_WINDOWS_VERBOSE_LOG=1`
- `DART_V2RAY_WINDOWS_CAPTURE_XRAY_IO=1`

Read logs:

```dart
final logs = await v2ray.getDesktopDebugLogs();
```

Build a report payload:

```dart
final report = await v2ray.buildWindowsBugReport(
  includeLogFiles: true,
);
```

## Status Stream Tips

On Windows, use these fields for robust UX decisions:

- `connectionState`
- `processRunning`
- `trafficSource`
- `statusReason`

`connectionState` now emits one canonical value (`CONNECTING`, `CONNECTED`,
`DISCONNECTED`, `AUTO_DISCONNECTED`, `ERROR`), while diagnostics fields help
distinguish "connected but idle" from real traffic/runtime failures.
