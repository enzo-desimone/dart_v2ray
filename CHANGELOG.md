## Unreleased

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
