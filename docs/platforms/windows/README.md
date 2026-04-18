# Windows Guide

This guide covers Windows-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: tested and working

## Requirements

- Run app with Administrator privileges for VPN/TUN workflows.
- Provide `xray.exe` (for bundled distribution, place it in
  `windows/bin/xray.exe` inside the plugin package).
- Provide `wintun.dll` only if you need TUN mode.

## Runtime Configuration

Start call:

```dart
await v2ray.start(
  remark: 'Windows profile',
  config: configJson,
  windowsRequireTun: false,
);
```

- `windowsRequireTun: true` forces TUN mode.
- `windowsRequireTun: false` allows proxy-mode operation without Wintun.

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
final logs = await v2ray.getWindowsDebugLogs();
```

Build a report payload:

```dart
final report = await v2ray.buildWindowsBugReport(
  includeLogFiles: true,
);
```

## Status Stream Tips

On Windows, use these fields for robust UX decisions:

- `state`
- `connectionPhase`
- `isProcessRunning`
- `trafficSource`
- `trafficReason`

This helps distinguish "connected but idle" from real traffic failures.
