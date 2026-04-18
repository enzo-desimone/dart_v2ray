# macOS Guide

This guide tracks macOS readiness for `dart_v2ray`.

## Current Status

- Plugin registration in `pubspec.yaml`: not yet enabled
- Native macOS plugin folder: not present in this repository snapshot

## What To Prepare

1. Add a macOS plugin implementation folder (`macos/`).
2. Register the macOS platform in `pubspec.yaml`.
3. Reuse or port the desktop shared core integration used by Linux/Windows.
4. Define distribution strategy for Xray binary and optional TUN dependencies.
5. Validate notarization/signing implications for bundled executables.

## Suggested Rollout

1. Start with proxy-only mode.
2. Add status stream parity with Windows/Linux fields.
3. Add TUN mode only after binary distribution and entitlement strategy are clear.

## Compatibility Note

The high-level Dart API is already platform-agnostic, so once native macOS
registration is added, app-layer Dart code usually requires minimal changes.
