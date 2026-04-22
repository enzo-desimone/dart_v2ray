# macOS Guide

This guide describes the **helper-tool-based** macOS architecture for `dart_v2ray`, designed for App Sandbox and Mac App Store-oriented packaging.

## Architecture Summary

`dart_v2ray` now uses a plugin-owned runtime layout:

```text
macos/
  runtime/
    xray
    geoip.dat
    geosite.dat
  runtime_helper/
    DartV2RayRuntimeHelper.swift
```

At build time, a plugin-owned CocoaPods script phase performs packaging into each consuming macOS target (app and/or extension target that integrates the pod):

- Copies runtime files to:
  - `Contents/Resources/dart_v2ray_runtime/`
- Compiles and embeds helper executable to:
  - `Contents/Helpers/dart_v2ray_runtime_helper`
- Signs nested executables (`xray`, helper) when code signing is enabled.

Runtime launch model:
- Plugin desktop core prefers launching `dart_v2ray_runtime_helper`.
- Helper resolves plugin runtime directory, sets `XRAY_LOCATION_ASSET`, then launches `xray`.

This replaces the previous raw-resource launch approach.

---

## Why this design

- Uses a structured embedded helper model compatible with sandboxed macOS apps.
- Keeps runtime packaging logic inside the plugin instead of per-project copy scripts.
- Reduces host-app integration to unavoidable Apple-project concerns (targets, entitlements, signing).

---

## Host integration (minimal)

### Proxy mode (`requireTun: false`)

No manual runtime copy steps are required.

### Packet Tunnel mode (`requireTun: true`)

You still need Apple-required host setup:

1. Add a Network Extension target (`XrayTunnel`).
2. Enable App Sandbox + Network Extensions + App Groups for Runner and extension.
3. Ensure extension target is code-signed with proper provisioning.
4. Ensure the extension target integrates CocoaPods so `dart_v2ray` script phase runs there too.

> The plugin can package runtime/helper for any target that integrates the pod. Creating/managing extension targets and entitlements remains host-project-specific by Apple design.

---

## Podfile pattern for extension integration

Example:

```ruby
target 'Runner' do
  use_frameworks!
  flutter_install_all_macos_pods File.dirname(File.realpath(__FILE__))
end

target 'XrayTunnel' do
  use_frameworks!
  flutter_install_all_macos_pods File.dirname(File.realpath(__FILE__))
end
```

If your extension should not link Flutter/plugin code directly, keep linkage minimal according to your project constraints, but ensure runtime packaging phase runs for the extension build product.

---

## Migration from old architecture

Old approach:
- Runtime in `macos/bin/`.
- Host-managed Run Script copied `xray`/`geo*.dat` into `.appex` resources.
- Extension launched copied raw `xray` directly.

New approach:
- Runtime moved to `macos/runtime/`.
- Plugin builds/embeds `dart_v2ray_runtime_helper` and packages runtime automatically.
- Desktop runtime resolution prefers helper in `Contents/Helpers`.

### What to remove from existing apps

- Remove custom extension Run Script phases that copied files from `.symlinks/plugins/dart_v2ray/macos/bin`.
- Remove references to `DART_V2RAY_MACOS_RUNTIME_DIR` and legacy `macos/bin` paths.

---

## Verification checklist

After building Runner and extension:

```bash
ls -l YourApp.app/Contents/Helpers/dart_v2ray_runtime_helper
ls -l YourApp.app/Contents/Resources/dart_v2ray_runtime/xray
ls -l YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Helpers/dart_v2ray_runtime_helper
ls -l YourApp.app/Contents/PlugIns/XrayTunnel.appex/Contents/Resources/dart_v2ray_runtime/xray
```

Both helper and `xray` must exist and be executable.

---

## What remains host-project-specific and why

1. **Creating Packet Tunnel target**: plugin cannot safely create/own arbitrary targets in every host Xcode project.
2. **Entitlements and provisioning**: tied to developer account/team IDs, profiles, and app identifiers.
3. **Signing policy decisions**: distribution/development signing is project-specific.
4. **Network Extension capability review posture**: App Store justification metadata is app-specific.

Everything else (runtime artifacts, packaging logic, helper launch model, runtime pathing) is now plugin-owned.
