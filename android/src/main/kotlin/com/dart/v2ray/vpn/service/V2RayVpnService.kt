package com.dart.v2ray.vpn.service

import com.dart.v2ray.vpn.xray.service.XrayVPNService

/**
 * Backward-compatibility service shim.
 *
 * Some host apps still reference the legacy class name
 * `com.dart.v2ray.vpn.service.V2RayVpnService` in their
 * AndroidManifest.xml (or from an existing Always-on VPN profile).
 *
 * Keep this class so old manifests/profiles continue to work after the
 * package moved to `xray.service.XrayVPNService`.
 */
class V2RayVpnService : XrayVPNService()


