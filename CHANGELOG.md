## Unreleased

- Expanded `ConnectionStatus` with lifecycle and diagnostics fields:
  `connectionPhase`, `transportMode`, `trafficSource`, `trafficReason`,
  and `isProcessRunning`.
- Improved Windows status payload semantics with connection phases
  (`VERIFYING`, `READY`, `ACTIVE`) and explicit `AUTO_DISCONNECTED` propagation.
- Added periodic status heartbeat on Windows event stream publishing
  to reduce stale UI status conditions.
- Updated example app to expose stronger connection-state visibility,
  console status logging, and periodic diagnostics polling.
- Updated English README/API docs for the new status model and
  Windows diagnostics interpretation.

## 0.1.0

- Initial public API for Xray/V2Ray connection management.
- Added Android, iOS, Windows, and Linux implementations using method/event channels.
- Added auto-disconnect controls and status stream model.
- Added Windows traffic diagnostics method for troubleshooting.
- Added URL parser support for VLESS, VMESS, Trojan, Shadowsocks, and Socks links.
- Replaced template sample and tests with plugin-specific examples/tests.
- iOS podspec no longer uses a hardcoded external framework URL; framework source is now provided by environment variables.
