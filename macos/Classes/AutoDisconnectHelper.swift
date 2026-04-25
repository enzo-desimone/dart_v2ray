import Foundation
import FlutterMacOS

final class AutoDisconnectHelper {
    static let shared = AutoDisconnectHelper()
    private init() {}

    private var groupIdentifier: String?
    private var appName: String = "VPN"
    private static let timestampKey = "dart_v2ray_auto_disconnect_timestamp"

    func configure(groupIdentifier: String?, appName: String, expiredMessage: String? = nil) {
        self.groupIdentifier = groupIdentifier
        self.appName = appName

        if let message = expiredMessage {
            AutoDisconnectNotificationManager.shared.configure(
                appName: appName,
                expiredMessage: message
            )
        }
    }

    func wasAutoDisconnected() -> Bool {
        return getUserDefaults().double(forKey: Self.timestampKey) > 0
    }

    func getAutoDisconnectTimestamp() -> Int64 {
        return Int64(getUserDefaults().double(forKey: Self.timestampKey))
    }

    func clearExpiredFlag() {
        let defaults = getUserDefaults()
        defaults.removeObject(forKey: Self.timestampKey)
        defaults.synchronize()
    }

    func checkAndHandleDisconnect(currentStatus: String) -> String {
        guard currentStatus == "DISCONNECTED" else {
            return currentStatus
        }

        if wasAutoDisconnected() {
            AutoDisconnectNotificationManager.shared.showExpiryNotification()
            return "AUTO_DISCONNECTED"
        }

        return currentStatus
    }

    func updateTime(call: FlutterMethodCall, packetTunnelManager: PacketTunnelManager?, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let additionalSeconds = arguments["additional_seconds"] as? Int else {
            result(-1)
            return
        }

        Task {
            do {
                let message = "auto_disconnect_update:\(additionalSeconds)"
                let response = try await packetTunnelManager?.sendProviderMessage(data: message.data(using: .utf8)!)
                if let response = response, let remaining = Int(String(decoding: response, as: UTF8.self)) {
                    result(remaining)
                } else {
                    result(-1)
                }
            } catch {
                result(-1)
            }
        }
    }

    func getRemainingTime(packetTunnelManager: PacketTunnelManager?, result: @escaping FlutterResult) {
        Task {
            do {
                let response = try await packetTunnelManager?.sendProviderMessage(data: "auto_disconnect_remaining".data(using: .utf8)!)
                if let response = response, let remaining = Int(String(decoding: response, as: UTF8.self)) {
                    result(remaining)
                } else {
                    result(-1)
                }
            } catch {
                result(-1)
            }
        }
    }

    func cancel(packetTunnelManager: PacketTunnelManager?, result: @escaping FlutterResult) {
        Task {
            do {
                let _ = try await packetTunnelManager?.sendProviderMessage(data: "auto_disconnect_cancel".data(using: .utf8)!)
                result(nil)
            } catch {
                result(nil)
            }
        }
    }

    func handleWasAutoDisconnected(result: @escaping FlutterResult) {
        result(wasAutoDisconnected())
    }

    func handleClearFlag(result: @escaping FlutterResult) {
        clearExpiredFlag()
        result(nil)
    }

    func handleGetTimestamp(result: @escaping FlutterResult) {
        result(getAutoDisconnectTimestamp())
    }

    private func getUserDefaults() -> UserDefaults {
        if let groupId = groupIdentifier, !groupId.isEmpty {
            return UserDefaults(suiteName: groupId) ?? UserDefaults.standard
        }
        return UserDefaults.standard
    }
}
