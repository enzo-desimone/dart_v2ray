# macOS architecture (App-Store friendly, no external `xray` executable)

Questo plugin ora usa **Xray core come libreria linkata** su macOS.

## Obiettivo

- Niente `Process` / `NSTask` / `posix_spawn` in Network Extension.
- Niente `xray` executable copiato in `Resources`.
- Core avviato in-process via bridge Go `c-archive` (`.a + .h`).

## Version pinning

- Go: **1.23.6** (esplicito in `macos/xray_bridge_go/go.mod` e `.tool-versions`).
- Xray core: **`github.com/xtls/xray-core v26.4.17`** (pinnato in `go.mod`).
- Bridge buildmode: `-buildmode=c-archive`.

## Struttura

```text
macos/xray_bridge_go/
  bridge.go
  go.mod
  .tool-versions
  include/libxraybridge.h
  scripts/build_macos_bridge.sh
  build/
    darwin_arm64/
    darwin_amd64/
    universal/
```

## API C del bridge

Header: `macos/xray_bridge_go/include/libxraybridge.h`

- `XrayStartFromConfigPath(const char*)`
- `XrayStartFromConfigJson(const char*)`
- `XrayStop()`
- `XrayVersion()`
- `XrayLastError()`
- `XrayFreeString(char*)`

## Build bridge (arm64 + amd64 + universal)

```bash
cd macos/xray_bridge_go
./scripts/build_macos_bridge.sh
```

Output:

- `macos/xray_bridge_go/build/universal/libxraybridge.a`
- `macos/xray_bridge_go/build/universal/libxraybridge.h`

## Integrazione CocoaPods/Xcode

`macos/dart_v2ray.podspec` ora:

- valida presenza degli artifact bridge in `prepare_command`;
- linka `xray_bridge_go/build/universal/libxraybridge.a` (`vendored_libraries`);
- include gli header path del bridge;
- **non** include più `bin/xray` in resources.

## Flusso runtime

1. Dart/Flutter invia JSON config al plugin macOS.
2. Native core salva il JSON in file temporaneo.
3. Su macOS, `DesktopV2rayCore::Start()` invoca `XrayStartFromConfigPath(...)`.
4. Bridge Go carica JSON (`core.LoadConfig("json", ...)`) e avvia `core.New(...).Start()`.
5. `Stop()` invoca `XrayStop()`.
6. `GetCoreVersion()` usa `XrayVersion()`.

## Integrazione target `XrayTunnel` (Network Extension)

Per il target extension della tua app host:

1. Aggiungi `libxraybridge.a` a **Link Binary With Libraries** del target extension.
2. Aggiungi `libxraybridge.h` in header search path o module map del target extension.
3. Usa un wrapper Swift minimale (`XrayBridge.swift`) che chiama le API C.
4. In `PacketTunnelProvider`, leggi config da App Group (o JSON string) e chiama il bridge.
5. Su stop del tunnel, chiama `XrayStop()`.

> Importante: non fare shell-out dalla extension.

## Troubleshooting

- Errore pod install su artifact mancanti:
  - Esegui `./macos/xray_bridge_go/scripts/build_macos_bridge.sh`.
- `XrayStart...` ritorna codice != 0:
  - Leggi `XrayLastError()` e verifica JSON/asset geo.
- Linker error su `Xray*`:
  - Verifica che il target stia linkando `libxraybridge.a` corretto (architettura/universal).

## Limiti noti

- Questo repo contiene il plugin Flutter; il codice effettivo del target `PacketTunnelProvider` dell'app host è esterno al plugin e va aggiornato nel progetto app.
