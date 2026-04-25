# macOS Setup Guide

Questa guida copre la configurazione di `dart_v2ray` su macOS (Intel + Apple Silicon) usando `LibXray.xcframework`.

## Requisiti

- macOS deployment target consigliato: **12.0+**.
- Xcode aggiornato (consigliato la stessa major usata dal tuo progetto Flutter).
- Account Apple Developer per firmare app + Network Extension.

## 1) Podfile del runner macOS

In `macos/Podfile` imposta:

```ruby
platform :osx, '12.0'
```

Poi esegui:

```bash
cd macos
pod install
```

## 2) Framework LibXray

Il plugin scarica automaticamente `LibXray.xcframework` durante `pod install` dal link:

- `https://besimsoft.com/macos/LibXray.xcframework.zip`

Per una pipeline più affidabile (best practice produzione/App Store), usa variabili ambiente:

- `DART_V2RAY_MACOS_FRAMEWORK_URL` (mirror interno o URL pinning)
- `DART_V2RAY_MACOS_FRAMEWORK_SHA256` (**fortemente consigliato**)
- `DART_V2RAY_MACOS_FRAMEWORK_ZIP_PATH` (file locale pre-scaricato in CI)

Esempio CI:

```bash
export DART_V2RAY_MACOS_FRAMEWORK_ZIP_PATH="$PWD/vendor/LibXray.xcframework.zip"
export DART_V2RAY_MACOS_FRAMEWORK_SHA256="<sha256-del-file>"
flutter build macos --release
```

## 3) Xcode capabilities (Runner)

Nel target **Runner (macOS)**:

- Abilita **App Sandbox**.
- Abilita capability **Network Extensions** con tipo **Packet Tunnel**.
- Aggiungi **App Groups** (stesso group usato dalla extension).

## 4) Packet Tunnel Extension target

Crea un target Network Extension chiamato `XrayTunnel`.

Configurazione minima:

- Stesso Team di signing del Runner.
- Bundle id coerente con il plugin: il plugin usa
  `"<providerBundleIdentifier>.XrayTunnel"`.
- App Group identico a quello del Runner.
- Entitlements Network Extension + App Group nel target extension.

## 5) Inizializzazione Flutter

In Dart passa identificatori coerenti:

```dart
await DartV2ray().initialize(
  providerBundleIdentifier: 'com.example.myapp',
  groupIdentifier: 'group.com.example.myapp',
);
```

> Il plugin risolverà automaticamente il bundle extension in
> `com.example.myapp.XrayTunnel`.

## 6) Note App Store (raccomandate)

Per massimizzare la probabilità di approvazione:

- Usa solo capability realmente necessarie (Network Extension + App Group).
- Mantieni privacy policy e descrizione d’uso rete coerenti con il comportamento VPN/proxy.
- Evita download runtime non verificati: usa SHA256 fisso o artefatti interni firmati in CI.
- Verifica che Runner + Extension abbiano provisioning profile corretti e consistenti.
- Testa sempre build Release firmata su macchina pulita prima dell’upload.

## 7) API supportate su macOS

Supporto allineato ai metodi principali del plugin:

- `initialize`, `requestPermission`, `start`, `stop`
- `getCoreVersion`, `getServerDelay`, `getConnectedServerDelay`
- auto-disconnect (`updateAutoDisconnectTime`, `getRemainingAutoDisconnectTime`, `cancelAutoDisconnect`, flag/timestamp)
- stream stato `onStatusChanged`

