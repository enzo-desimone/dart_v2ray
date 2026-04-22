# dart_v2ray

Plugin Flutter/Dart per gestire connessioni **Xray/V2Ray** da codice Dart con API ad alto livello, stream di stato, parsing share-link e strumenti diagnostici (in particolare su Windows).

> Stato attuale supporto piattaforme: **Android, iOS, Windows**.
>
> Il supporto per altre piattaforme **non è al momento disponibile/attivo nel repository corrente** e verrà esteso in futuro.

---

## Indice

- [Panoramica](#panoramica)
- [Obiettivo del progetto](#obiettivo-del-progetto)
- [Supporto piattaforme](#supporto-piattaforme)
- [Installazione](#installazione)
- [Requisiti](#requisiti)
- [Configurazione per piattaforma](#configurazione-per-piattaforma)
- [Quick start](#quick-start)
- [API pubbliche](#api-pubbliche)
  - [`DartV2ray`](#dartv2ray-classe-principale)
  - [Modelli pubblici](#modelli-pubblici)
  - [Share-link parser](#share-link-parser)
- [Flusso logico del plugin](#flusso-logico-del-plugin)
- [Note architetturali essenziali](#note-architetturali-essenziali)
- [Limitazioni note](#limitazioni-note)
- [Troubleshooting](#troubleshooting)
- [Roadmap / Future support](#roadmap--future-support)
- [Documentazione aggiuntiva](#documentazione-aggiuntiva)

---

## Panoramica

`dart_v2ray` espone un'API unificata per:

- inizializzazione componente nativa;
- richiesta permessi / privilegi;
- avvio e stop sessione con JSON Xray;
- monitoraggio stato e traffico in tempo reale;
- gestione auto-disconnessione;
- parsing di link `vmess://`, `vless://`, `trojan://`, `ss://`, `socks://` in configurazione Xray completa.

Entrypoint pubblico principale:

```dart
import 'package:dart_v2ray/dart_v2ray.dart';
```

---

## Obiettivo del progetto

Offrire un layer Dart stabile e riusabile sopra implementazioni native (method/event channel), così da integrare V2Ray/Xray in app Flutter senza gestire direttamente i dettagli platform-specific in ogni progetto.

---

## Supporto piattaforme

### Supportate ad oggi

- ✅ Android
- ✅ iOS
- ✅ Windows

### Non disponibili al momento

- ❌ macOS
- ❌ Linux
- ❌ Web

> Nota: nel repository sono presenti riferimenti storici/documentali a Linux/macOS, ma la base plugin attuale è da considerare operativa su Android/iOS/Windows.

---

## Installazione

```yaml
dependencies:
  dart_v2ray: ^0.1.0
```

```bash
flutter pub get
```

---

## Requisiti

- Dart SDK `^3.7.2`
- Flutter `>=3.3.0`

### Requisiti runtime rilevanti

- **Android**: `minSdkVersion >= 23`, VPN permission flow.
- **iOS**: iOS 15+, Network Extension (Packet Tunnel), App Group.
- **Windows**: privilegi amministratore raccomandati/necessari per workflow TUN.

---

## Configurazione per piattaforma

## Android

- Assicurati che il tuo `AndroidManifest`/`application` includa:

```xml
android:extractNativeLibs="true"
```

- Imposta `minSdkVersion >= 23`.
- Gestisci correttamente disclosure/privacy policy se l'app intercetta/modifica traffico (es. linee guida store).

## iOS

Configurazione minima:

1. `platform :ios, '15.0'` nel Podfile.
2. `pod install` in `ios/`.
3. Capability su Runner:
   - App Group
   - Network Extension (Packet Tunnel)
4. Crea target extension (es. `XrayTunnel`) con stesse capability.
5. In Flutter passa identificativi coerenti in `initialize(...)`:

```dart
await v2ray.initialize(
  providerBundleIdentifier: 'com.example.app.XrayTunnel',
  groupIdentifier: 'group.com.example.app',
);
```

## Windows

- Build/runtime includono download automatico di Xray (`xray.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`) via CMake quando non presenti localmente.
- Per CI/offline o mirror custom puoi usare variabili `DART_V2RAY_WINDOWS_XRAY_*` e `DART_V2RAY_XRAY_VERSION`.
- Usa `requireTun: true` per modalità TUN di sistema; `false` per proxy-only.

---

## Quick start

```dart
import 'package:dart_v2ray/dart_v2ray.dart';

final DartV2ray v2ray = DartV2ray();

Future<void> connectWithConfig(String configJson) async {
  await v2ray.initialize(
    providerBundleIdentifier: 'com.example.app.XrayTunnel', // iOS only
    groupIdentifier: 'group.com.example.app',               // iOS only
  );

  final bool granted = await v2ray.requestPermission();
  if (!granted) return;

  await v2ray.start(
    remark: 'My profile',
    config: configJson,
    requireTun: true,
  );

  v2ray.onStatusChanged.listen((VpnStatus s) {
    print('state=${s.connectionState} up=${s.uploadSpeedBps} down=${s.downloadSpeedBps}');
  });
}
```

Stop:

```dart
await v2ray.stop();
```

---

## API pubbliche

## `DartV2ray` (classe principale)

Classe high-level che orchestra validazione config, chiamate platform e stream stato.

### Metodi principali

- `requestPermission()`
- `initialize(...)`
- `start(...)`
- `stop()`
- `getServerDelay(...)`
- `getConnectedServerDelay(...)`
- `getCoreVersion()`

### Diagnostica e debug

- `configureWindowsDebugLogging(...)`
- `getWindowsTrafficDiagnostics()`
- `getDesktopDebugLogs(...)`
- `buildWindowsBugReport(...)`

### Auto-disconnect

- `updateAutoDisconnectTime(...)`
- `getRemainingAutoDisconnectTime()`
- `cancelAutoDisconnect()`
- `wasAutoDisconnected()`
- `clearAutoDisconnectFlag()`
- `getAutoDisconnectTimestamp()`

### Stream e listener persistente

- `onStatusChanged`
- `startPersistentStatusListener()`
- `persistentStatusStream`
- `latestStatus`
- `stopPersistentStatusListener()`
- `dispose()`

### Utility statica

- `DartV2ray.parseShareLink(String link)`

---

## Modelli pubblici

## `VpnConnectionState` (enum)

Valori canonici:

- `connecting`
- `connected`
- `disconnected`
- `autoDisconnected`
- `error`

## `VpnStatus` (classe)

Campi pubblici principali:

- `sessionSeconds`
- `uploadSpeedBps`, `downloadSpeedBps`
- `uploadedBytes`, `downloadedBytes`
- `connectionState`
- `transportMode`
- `trafficSource`
- `statusReason`
- `processRunning`
- `autoDisconnectRemainingSeconds`

Helper utili:

- getter `isConnected`, `isConnecting`, `isDisconnected`, `isAutoDisconnected`, `isError`
- `copyWith(...)`
- `toMap()`
- `VpnStatus.resolveState(...)` per normalizzare stati nativi

## `AutoDisconnectConfig` + enum correlati

- `AutoDisconnectConfig`
- `AutoDisconnectExpireBehavior`
- `AutoDisconnectTimeFormat`

Costruttori:

- `AutoDisconnectConfig(...)`
- `AutoDisconnectConfig.disabled()`

Metodo:

- `toMap()`

---

## Share-link parser

Tipi pubblici:

- `V2rayUrl` (astratta)
- `VmessUrl`
- `VlessUrl`
- `TrojanUrl`
- `ShadowsocksUrl`
- `SocksUrl`

Uso tipico:

```dart
final V2rayUrl parsed = DartV2ray.parseShareLink(link);
final String configJson = parsed.getFullConfiguration();

await v2ray.start(
  remark: parsed.remark,
  config: configJson,
  requireTun: false,
);
```

Metodi importanti di `V2rayUrl`:

- `getFullConfiguration(...)`
- `getFullConfigurationWithLogs(...)`
- `populateTransportSettings(...)`
- `populateTlsSettings(...)`
- `removeNulls(...)`

---

## Flusso logico del plugin

1. L’app chiama `initialize(...)`.
2. Richiede permessi/privilegi con `requestPermission()`.
3. Crea/valida config JSON (`start(...)` invoca validazione `outbounds`).
4. Avvia sessione nativa via method channel (`startVless`).
5. Riceve eventi su `dart_v2ray/status`, parsati in `VpnStatus`.
6. Opzionalmente usa listener persistente (`PersistentStatusController`) per mantenere uno snapshot consistente anche quando la UI si disiscrive.
7. Ferma sessione con `stop()` e libera risorse con `dispose()`.

---

## Note architetturali essenziali

- **Public API layer**: `lib/dart_v2ray.dart` esporta modelli e componenti pubblici.
- **Platform abstraction**: `DartV2rayPlatform` + `MethodChannelDartV2ray`.
- **Status pipeline**: `StatusEventParser` → `VpnStatus`.
- **Windows resiliency**: fallback diagnostico (`WindowsStatusFallbackMapper`) e builder report (`WindowsBugReportBuilder`).
- **Legacy compatibility**: in `lib/url/*` ci sono export retrocompatibili verso `lib/src/share_links/*`.

---

## Limitazioni note

- Il metodo channel usa nomi storici (`initializeVless`, `startVless`, `stopVless`) anche per protocolli diversi: comportamento voluto per compatibilità, ma naming non perfettamente semantico.
- `validateXrayConfig` effettua una validazione minima (JSON valido + `outbounds` non vuoto): non sostituisce una validazione completa di tutte le sezioni Xray.
- Le diagnostiche avanzate (`configureWindowsDebugLogging`, `buildWindowsBugReport`, `getWindowsTrafficDiagnostics`) hanno valore soprattutto su Windows.

---

## Troubleshooting

### `ArgumentError` in `start(...)`

Verifica che la config:

- sia JSON valido;
- sia un oggetto JSON;
- contenga almeno un outbound in `outbounds`.

### Nessun evento di stato in UI

- Avvia ascolto `onStatusChanged` prima/durante `start(...)`.
- Se la UI ricrea spesso listener, usa `startPersistentStatusListener()` e `persistentStatusStream`.

### iOS non connette

- Controlla che `providerBundleIdentifier` e `groupIdentifier` passati a `initialize(...)` corrispondano ai target/capability configurati in Xcode.

### Windows: sessione non parte in TUN

- Avvia l’app con privilegi amministratore.
- Verifica presenza/download runtime e configurazione variabili `DART_V2RAY_WINDOWS_XRAY_*` in caso di CI/offline.

---

## Roadmap / Future support

- Estendere supporto ufficiale ad altre piattaforme desktop/mobile.
- Migliorare validazione config con diagnostica più granulare.
- Uniformare naming storico method-channel quando possibile, mantenendo retrocompatibilità.

---

## Documentazione aggiuntiva

- Indice docs: `docs/README.md`
- Guide storiche per piattaforma:
  - `docs/platforms/android/README.md`
  - `docs/platforms/ios/README.md`
  - `docs/platforms/windows/README.md`
  - `docs/platforms/linux/README.md` (non implementato)
  - `docs/platforms/macos/README.md` (non implementato)

---

## Sviluppo

```bash
flutter pub get
dart format lib
flutter analyze
flutter test
```

## License

MIT
