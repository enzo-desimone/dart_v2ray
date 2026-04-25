# Linux Setup Guide

Linux è supportato dal layer Dart e dal runtime desktop, ma la configurazione dipende dalla distribuzione e dal packaging scelto.

## Checklist rapida

- Distribuisci `xray` e i data file richiesti (`geoip.dat`, `geosite.dat`) nel package finale.
- Se usi modalità TUN (`requireTun: true`), configura capabilities/permessi necessari del sistema.
- Testa su ogni distro target (Ubuntu, Debian, Fedora, ecc.) perché networking e permessi cambiano.

## Inizializzazione

```dart
await DartV2ray().initialize(
  providerBundleIdentifier: '',
  groupIdentifier: '',
);
```

I parametri Apple-specific non sono usati su Linux ma restano nel contratto API cross-platform.
