import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {
  private let logger = Logger(subsystem: "com.example.xraytunnel", category: "PacketTunnelProvider")
  private let xrayBridge = XrayBridge()

  override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    do {
      let appGroupId = "group.com.kly.connect" // TODO: inject from providerConfiguration
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
      guard let container else {
        completionHandler(NSError(domain: "XrayTunnel", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Missing app group container"]))
        return
      }

      let configPath = container.appendingPathComponent("xray-config.json").path
      logger.info("Starting Xray from config path: \(configPath, privacy: .public)")
      try xrayBridge.start(configPath: configPath)

      completionHandler(nil)
    } catch {
      logger.error("Failed to start Xray: \(error.localizedDescription, privacy: .public)")
      completionHandler(error)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    logger.info("Stopping Xray tunnel. reason=\(reason.rawValue)")
    xrayBridge.stop()
    completionHandler()
  }
}
