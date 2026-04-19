# iOS Guide

This guide covers iOS-specific setup for `dart_v2ray`.

## Current Status

- Plugin implementation: available
- Team validation status: not listed as fully tested in this repository cycle

## Required Native Setup

1. Add a Packet Tunnel Network Extension target.
2. Configure a shared App Group for app + extension.
3. Pass matching identifiers to `initialize(...)`.
4. Provide an `XRay.xcframework` source before `pod install`.

## Initialize

```dart
await v2ray.initialize(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

`providerBundleIdentifier` and `groupIdentifier` must match your native iOS
provisioning setup.

## Start

```dart
await v2ray.start(
  remark: 'iOS profile',
  config: configJson,
  requireTun: true,
);
```

## Connection Mode

- iOS uses the Packet Tunnel extension flow.
- `requireTun` is accepted by the Dart API for consistency, but iOS currently
  runs through the extension path (no proxy-only switch).

## Framework Source

By default, the plugin downloads this hosted archive and verifies it with SHA256:

```text
https://github.com/shafiquecbl/flutter_v2ray_plus/releases/download/framework-v1.0.0/XRay.xcframework.zip
SHA256: ab14d797a3efe5cd148054e7bd1923d95b355cee9b0a36e5a81782c6fd517d1a
```

No extra setup is required for default behavior.

If you need a different source, configure one of the following before `pod install`:

```bash
# Option 1: local archive
export DART_V2RAY_IOS_FRAMEWORK_ZIP_PATH=/absolute/path/XRay.xcframework.zip

# Option 2: hosted archive
export DART_V2RAY_IOS_FRAMEWORK_URL=https://your-domain/releases/XRay.xcframework.zip
export DART_V2RAY_IOS_FRAMEWORK_SHA256=your_sha256_here
```

## Troubleshooting

- Extension cannot start: verify Packet Tunnel target and entitlements.
- No data exchange between app and extension: verify App Group string matches
  exactly across targets.
- Pod install issues: check framework env variables and URL/hash correctness.
