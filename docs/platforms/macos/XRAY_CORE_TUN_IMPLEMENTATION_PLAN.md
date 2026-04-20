# macOS full-tunnel: implementation plan based on Xray-core

Questo documento definisce **come implementare il full tunnel su macOS usando le primitive di Xray-core**, invece di basarsi su workaround locali.

## Stato implementazione nel plugin

Nel plugin macOS sono ora già disponibili i metadati base per la extension
Packet Tunnel via `providerConfiguration`:

- pass-through di `dnsServers` e `bypassSubnets` dal layer Dart;
- estrazione automatica di `excludedRemoteHosts` dalla sezione `outbounds`
  della config Xray (utile per anti-loop);
- flag di capability `tunDriver=xray_fd`,
  `tunFdEnvironmentKey=XRAY_TUN_FD`, `requireTun=true`.

Quindi la parte rimanente principale è la **logica nella tua Network Extension**
che usa questi campi per programmare routing/DNS e lanciare `xray` con FD utun.

## Perché su macOS oggi fallisce più spesso

Dalla documentazione ufficiale di Xray emerge che:

- l'inbound `tun` crea/interpreta l'interfaccia TUN ma **non configura automaticamente routing/DNS a livello OS**;
- il rischio principale è il **routing loop** (il traffico di Xray verso il suo server rientra nel tunnel);
- su macOS la modalità usa interfacce `utunN` e richiede policy di sistema coerenti.

In pratica, su desktop macOS non basta “accendere TUN”: serve orchestrazione di rete completa.

## Decisione architetturale

Per il plugin Flutter su macOS usare due modalità chiare:

1. **Proxy mode (`requireTun=false`)**
   - Xray gira come processo locale con inbound socks/http/mixed.
   - Nessuna manipolazione routing di sistema.

2. **VPN mode (`requireTun=true`)**
   - Usare **NetworkExtension / Packet Tunnel** come “owner” della rete.
   - Passare i pacchetti utun a Xray-core tramite FD (`xray.tun.fd` / `XRAY_TUN_FD`) oppure pipeline tun2socks ben isolata.
   - Tenere routing e DNS nel dominio NetworkExtension (non nel processo host app).

> Nota: questa impostazione evita la dipendenza da route shell globali in app desktop e si allinea al modello Apple per VPN user-space.

## Blueprint tecnico consigliato

### 1) Runtime Xray-core all'interno della Packet Tunnel Extension

- Bundle di `xray`, `geoip.dat`, `geosite.dat` dentro la extension target.
- Avvio di Xray **dalla extension**, non dalla Runner app.
- Logging separato per extension (file in App Group container).

### 2) Inbound TUN guidato da FD (approccio primario)

- Recuperare FD utun dalla `NEPacketTunnelProvider`.
- Esportare env var `XRAY_TUN_FD=<fd>` prima dell'avvio processo Xray.
- Config Xray con inbound `protocol: "tun"` coerente con la FD ricevuta.

Perché questo è il percorso più robusto:

- Xray-core documenta esplicitamente FD mode per mobile Apple;
- riduce conversioni doppie pacchetto→socks→pacchetto;
- minimizza mismatch tra stack utun Apple e stack userspace.

### 3) Routing anti-loop obbligatorio

Regole minime da applicare nel provider:

- default route nel tunnel per il traffico utente;
- esclusione esplicita dell'IP/endpoint del server VLESS (e fallback endpoints);
- canale DNS del tunnel dedicato (resolver interno Xray o DNS remoto nel tunnel);
- blocco/gestione del leak DNS fuori tunnel.

Se non si escludono gli upstream di Xray, il loop è quasi garantito.

### 4) DNS strategy

- Forzare DNS del tunnel via `NEDNSSettings`.
- Coerenza con `dns` in config Xray (DoH/DoQ/local resolver secondo policy).
- Gestire split DNS solo se richiesto dal prodotto; altrimenti full DNS through tunnel.

### 5) Lifecycle robusto

- Start sequence:
  1. prepara `NEPacketTunnelNetworkSettings`;
  2. applica settings;
  3. avvia Xray;
  4. pubblica stato CONNECTED solo dopo handshake ok.
- Stop sequence:
  1. stop Xray;
  2. chiusura FD/tun resources;
  3. cleanup timer e stato.

### 6) Observability

Metriche minime da esporre a Flutter:

- stato tunnel (`CONNECTING/CONNECTED/DISCONNECTED/ERROR`),
- ultimo errore startup,
- byte up/down,
- motivo di disconnessione (manuale, auto-disconnect, errore runtime).

## Piano di rollout

### Fase A — Foundation

- Isolare un runner Xray dentro extension con input JSON validato.
- Garantire packaging runtime files nella extension.
- Implementare log collection via App Group.

### Fase B — TUN FD path

- Wiring utun FD -> `XRAY_TUN_FD`.
- Config template Xray per full tunnel.
- Health-check startup e timeout deterministico.

### Fase C — Routing/DNS hardening

- Excluded routes per upstream.
- DNS full-tunnel + leak checks.
- Recovery automatico su cambio rete.

### Fase D — QA matrix

- macOS Intel + Apple Silicon,
- Wi‑Fi/Ethernet,
- captive portal,
- sleep/wake,
- network switch,
- reconnect con server down/up.

## Criteri di accettazione (Definition of Done)

- `requireTun=true` su macOS instrada realmente tutto il traffico utente nel tunnel.
- Nessun leak DNS rilevabile nei test standard.
- Nessun loop verso endpoint VLESS primario/fallback.
- Riavvio tunnel stabile dopo sleep/wake e cambio interfaccia.
- Telemetria/stato coerenti verso layer Flutter.

## Cosa NON fare

- Non basare la soluzione su script `route` globali lanciati dalla app host.
- Non marcare CONNECTED prima che utun + Xray siano effettivamente operativi.
- Non mescolare responsabilità routing tra app host e extension.

## Riferimenti primari

- Xray TUN inbound docs (stato supporto generale e limiti):
  https://xtls.github.io/en/config/inbounds/tun.html
- Xray-core TUN README (routing loop, macOS `utun`, FD mode iOS/macOS context):
  https://github.com/XTLS/Xray-core/blob/main/proxy/tun/README.md
