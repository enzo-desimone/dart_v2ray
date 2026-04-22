## Unreleased

### macOS — self-contained runtime packaging

- Runtime files (`xray`, `geoip.dat`, `geosite.dat`) are now committed directly
  inside the plugin at `macos/bin/`. The plugin is self-contained on macOS and
  requires no host-app setup before `pod install`.
- `xray` is a universal binary (arm64 + x86_64) built with `lipo -create`.
- `dart_v2ray.podspec` `prepare_command` simplified: verifies files exist at
  `$(pwd)/bin/` (always the plugin's own `macos/bin/`), runs `chmod +x xray`,
  and exits with a clear error if any file is missing. All host-app copy logic
  and `DART_V2RAY_MACOS_RUNTIME_DIR` fallback removed.
- Removed `macos/bin/xray`, `macos/bin/geoip.dat`, `macos/bin/geosite.dat`
  from `.gitignore` so runtime files can be tracked.

### macOS — `XrayTunnel` extension packaging

- Added documentation and Run Script for the `XrayTunnel` Packet Tunnel target
  to copy runtime files from the plugin's `macos/bin/` into the extension bundle
  at build time (`TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH`).
- Documented requirement to set `ENABLE_USER_SCRIPT_SANDBOXING = No` on the
  `XrayTunnel` target to allow the Run Script to write to the build directory.
- Documented correct Xcode Build Phases order for `Runner` to avoid dependency
  cycle errors when `XrayTunnel.appex` is embedded.
- Documented framework embedding rules: `NetworkExtension.framework` and
  `Pods_XrayTunnel.framework` must be `Do Not Embed` in the extension target;
  `XrayTunnel.appex` must be `Embed Without Signing` in `Runner`.

- Refactored Dart sources into a clearer structure:
  `lib/src/core`, `lib/src/platform`, and `lib/src/share_links`.
- Split persistent status and Windows diagnostics logic into dedicated helper
  files to keep `DartV2ray` focused and easier to maintain.
- Added backward-compatible export wrappers for legacy import paths
  (`lib/url/*`, `dart_v2ray_method_channel.dart`,
  `dart_v2ray_platform_interface.dart`).
- Revised and expanded English DartDoc comments across public API and share-link
  parsers.
- Rewrote the global README and added platform-specific guides under
  `docs/platforms/*`.

- Replaced `ConnectionStatus` with `VpnStatus` and introduced
  `VpnConnectionState` as the canonical status enum.
- Renamed status fields to the new API:
  `connectionState`, `sessionSeconds`, `uploadSpeedBps`, `downloadSpeedBps`,
  `uploadedBytes`, `downloadedBytes`, `processRunning`, `statusReason`,
  `autoDisconnectRemainingSeconds`.
- Removed legacy phase-based surface and all backward-compatible aliases.
- Added `ERROR` propagation across Android/iOS/macOS/desktop flows so startup
  and runtime failures are surfaced through `onStatusChanged`.
- Added periodic status heartbeat on Windows event stream publishing
  to reduce stale UI status conditions.
- Updated example app to expose stronger connection-state visibility,
  console status logging, and periodic diagnostics polling.
- Updated English README/API docs for the new status model and
  Windows diagnostics interpretation.
- iOS podspec now uses a default hosted `XRay.xcframework.zip` URL with
  SHA256 verification, while still allowing environment-variable overrides.
- Added native macOS plugin registration and implementation reusing the shared
  desktop core (`macos/`), including status stream and auto-disconnect methods.
- macOS podspec no longer auto-downloads Xray runtime archives; runtime files are now expected to be provided manually (or via `DART_V2RAY_MACOS_RUNTIME_DIR`).

## 0.1.0

- Initial public API for Xray/V2Ray connection management.
- Added Android, iOS, Windows, and Linux implementations using method/event channels.
- Added auto-disconnect controls and status stream model.
- Added Windows traffic diagnostics method for troubleshooting.
- Added URL parser support for VLESS, VMESS, Trojan, Shadowsocks, and Socks links.
- Replaced template sample and tests with plugin-specific examples/tests.
- iOS podspec no longer uses a hardcoded external framework URL; framework source is now provided by environment variables.
