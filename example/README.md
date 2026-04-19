# dart_v2ray_example

This example demonstrates a plugin-oriented workflow for `dart_v2ray` with
focus on reliable connection-state visibility and troubleshooting.

## What It Shows

- Plugin initialization and permission flow
- Share-link import (`vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`)
- Start/stop session controls with guarded button states
- Live status surface (`connectionState`, traffic counters/speeds + diagnostics fields)
- Windows diagnostics and debug log retrieval
- Optional console status logging and periodic diagnostics polling

## Run

From the plugin root:

```bash
cd example
flutter pub get
flutter run
```

## Windows Troubleshooting

In the example UI, enable `Console status logs` to print:

- status stream events (`[dart_v2ray][status]`)
- periodic Windows diagnostics (`[dart_v2ray][diag]`)

Use `Reset logs` and `Show logs` to inspect plugin and Xray log tails quickly.
