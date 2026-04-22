# Android Guide

This guide covers Android-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: tested and working

## Requirements

- Flutter app with Android support enabled
- Android VPN permission flow accepted by the user
- ARM device or ARM emulator for bundled native binaries

## Initialize and Start

```dart
final DartV2ray v2ray = DartV2ray();

await v2ray.initialize(
  notificationIconResourceType: 'mipmap',
  notificationIconResourceName: 'ic_launcher',
  allowVpnFromSettings: true,
);

final bool granted = await v2ray.requestPermission();
if (!granted) return;

await v2ray.start(
  remark: 'Android profile',
  config: configJson,
  requireTun: true,
  notificationDisconnectButtonName: 'DISCONNECT',
  showNotificationDisconnectButton: true,
);
```

## Optional Android Arguments in `start(...)`

- `blockedApps`: package names to block in VPN mode.
- `bypassSubnets`: subnets excluded from tunnel.
- `dnsServers`: custom DNS resolver list.
- `requireTun`: `true` for full-device VPN/TUN, `false` for proxy-only mode.

## ABI Note

The plugin currently bundles:

- `arm64-v8a`
- `armeabi-v7a`

If you run on `x86` or `x86_64` emulators, startup can fail unless you provide
compatible native binaries for `libxray.so` and `libtun2socks.so`.

## Troubleshooting

- Permission denied: call `requestPermission()` before `start(...)`.
- Connection fails during startup/runtime: inspect
  `onStatusChanged.connectionState` and `statusReason`
  (`ERROR` is emitted when failure is detected).
- Connection starts but no traffic: inspect `transportMode`,
  `trafficSource`, and `processRunning`.
- Emulator failures: switch to ARM image or physical ARM device.
