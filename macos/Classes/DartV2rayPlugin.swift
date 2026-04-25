import Foundation
import FlutterMacOS
import NetworkExtension
import Combine

#if canImport(LibXray)
import LibXray
#elseif canImport(XRay)
import XRay
#endif

public class DartV2rayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var packetTunnelManager: PacketTunnelManager? = nil
    private var appName: String = "VPN"

    private var timer: Timer?
    private var eventSink: FlutterEventSink?
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0
    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0
    private var isStarting: Bool = false
    private var statusCancellable: AnyCancellable?
    private var lastStatus: String = "DISCONNECTED"
    private var lastErrorMessage: String = ""

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dart_v2ray", binaryMessenger: registrar.messenger)
        let instance = DartV2rayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "dart_v2ray/status", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        DispatchQueue.main.async { [weak self] in
            self?.handleStatusChange()
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    private func buildStatusPayload(seconds: Int, status: String, remainingTime: String?) -> [Any] {
        let normalizedStatus = status.uppercased()
        let isRunning = normalizedStatus == "CONNECTED" || normalizedStatus == "CONNECTING"
        let source = normalizedStatus == "CONNECTED" ? "packet_tunnel" : ""
        let reason = normalizedStatus == "ERROR" ? lastErrorMessage : ""

        return [
            "\(seconds)",
            "\(self.uploadSpeed)",
            "\(self.downloadSpeed)",
            "\(self.totalUpload)",
            "\(self.totalDownload)",
            normalizedStatus,
            remainingTime ?? NSNull(),
            normalizedStatus,
            "tun",
            source,
            reason,
            isRunning ? "true" : "false"
        ]
    }

    private func emitStatusEvent(seconds: Int = 0, status: String, remainingTime: String? = nil) {
        self.eventSink?(buildStatusPayload(seconds: seconds, status: status, remainingTime: remainingTime))
    }

    private func startTimer() {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }

            let status = self.lastStatus

            if status == "CONNECTED" {
                let elapsed = Date().timeIntervalSince(self.packetTunnelManager?.connectedDate ?? Date())
                let seconds = Int(elapsed)

                Task {
                    do {
                        let trafficResponse = try await self.packetTunnelManager?.sendProviderMessage(data: "xray_traffic".data(using: .utf8)!)
                        if let trafficResponse = trafficResponse {
                            let traffic = String(decoding: trafficResponse, as: UTF8.self)
                            let parts = traffic.split(separator: ",")
                            if parts.count >= 2, let up = Int(parts[0]), let down = Int(parts[1]) {
                                await MainActor.run {
                                    self.uploadSpeed = up - self.totalUpload
                                    self.downloadSpeed = down - self.totalDownload
                                    self.totalUpload = up
                                    self.totalDownload = down
                                }
                            }
                        }

                        let remainingResponse = try await self.packetTunnelManager?.sendProviderMessage(data: "auto_disconnect_remaining".data(using: .utf8)!)
                        let remainingTimeStr: String?
                        if let remainingResponse = remainingResponse {
                            let remaining = String(decoding: remainingResponse, as: UTF8.self)
                            if let remainingInt = Int(remaining), remainingInt >= 0 {
                                remainingTimeStr = remaining
                            } else {
                                remainingTimeStr = nil
                            }
                        } else {
                            remainingTimeStr = nil
                        }

                        await MainActor.run {
                            self.emitStatusEvent(seconds: seconds, status: status, remainingTime: remainingTimeStr)
                        }
                    } catch {
                        await MainActor.run {
                            self.emitStatusEvent(seconds: seconds, status: status)
                        }
                    }
                }
            } else {
                self.emitStatusEvent(seconds: 0, status: status)
            }
        })
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
        self.uploadSpeed = 0
        self.downloadSpeed = 0
        self.totalUpload = 0
        self.totalDownload = 0
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestPermission":
            requestPermission(result: result)
        case "initializeVless":
            initializeVless(call: call, result: result)
        case "startVless":
            startVless(call: call, result: result)
        case "stopVless":
            stopVless(result: result)
        case "getCoreVersion":
            getCoreVersion(result: result)
        case "getConnectedServerDelay":
            getConnectedServerDelay(call: call, result: result)
        case "getServerDelay":
            getServerDelay(call: call, result: result)
        case "updateAutoDisconnectTime":
            updateAutoDisconnectTime(call: call, result: result)
        case "getRemainingAutoDisconnectTime":
            getRemainingAutoDisconnectTime(result: result)
        case "cancelAutoDisconnect":
            cancelAutoDisconnect(result: result)
        case "wasAutoDisconnected":
            wasAutoDisconnected(result: result)
        case "clearAutoDisconnectFlag":
            clearAutoDisconnectFlag(result: result)
        case "getAutoDisconnectTimestamp":
            getAutoDisconnectTimestamp(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func stopVless(result: FlutterResult) {
        packetTunnelManager?.stop()
        stopTimer()
        result(nil)
    }

    private func getConnectedServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getConnectedServerDelay.", details: nil))
            return
        }
        Task {
            do {
                let delay = try await packetTunnelManager?.sendProviderMessage(data: "xray_delay\(url)".data(using: .utf8)!) ?? "-1".data(using: .utf8)!
                result(Int(String(decoding: delay, as: UTF8.self)))
            } catch {
                result(-1)
            }
        }
    }

    private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String,
              let config = arguments["config"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getServerDelay.", details: nil))
            return
        }

        #if canImport(LibXray) || canImport(XRay)
        Task {
            var error: NSError?
            var delay: Int64 = -1
            XRayMeasureOutboundDelay(config, url, &delay, &error)
            result(delay)
        }
        #else
        _ = config
        _ = url
        result(-1)
        #endif
    }

    private func startVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !isStarting else {
            result(FlutterError(code: "BUSY", message: "VPN is already starting.", details: nil))
            return
        }

        guard let arguments = call.arguments as? [String: Any],
              let remark = arguments["remark"] as? String,
              let config = arguments["config"] as? String,
              let configData = config.data(using: .utf8) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for startVless.", details: nil))
            return
        }

        let dnsServers = arguments["dns_servers"] as? [String]
        let autoDisconnect = arguments["auto_disconnect"] as? [String: Any]

        AutoDisconnectHelper.shared.configure(
            groupIdentifier: packetTunnelManager?.groupIdentifier,
            appName: appName,
            expiredMessage: autoDisconnect?["expiredNotificationMessage"] as? String
        )

        packetTunnelManager?.remark = remark
        packetTunnelManager?.xrayConfig = configData
        packetTunnelManager?.dnsServers = dnsServers
        packetTunnelManager?.autoDisconnect = autoDisconnect
        self.lastErrorMessage = ""

        isStarting = true
        Task {
            do {
                try await packetTunnelManager?.saveToPreferences()
                try await packetTunnelManager?.start()
                await MainActor.run {
                    self.isStarting = false
                    result(nil)
                }
            } catch {
                await MainActor.run {
                    self.isStarting = false
                    self.lastErrorMessage = "Failed to start VPN: \(error.localizedDescription)"
                    self.lastStatus = "ERROR"
                    self.stopTimer()
                    self.emitStatusEvent(status: "ERROR")
                    result(FlutterError(code: "VPN_ERROR", message: "Failed to start VPN: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    private func requestPermission(result: @escaping FlutterResult) {
        Task {
            let isGranted = await packetTunnelManager?.testSaveAndLoadProfile() ?? false
            result(isGranted)
        }
    }

    private func getCoreVersion(result: @escaping FlutterResult) {
        #if canImport(LibXray) || canImport(XRay)
        Task {
            result(XRayGetVersion())
        }
        #else
        result("unknown")
        #endif
    }

    private func initializeVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let providerBundleIdentifier = arguments["providerBundleIdentifier"] as? String,
              let groupIdentifier = arguments["groupIdentifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeVless.", details: nil))
            return
        }

        if let customAppName = arguments["appName"] as? String {
            self.appName = customAppName
        } else if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            self.appName = displayName
        } else if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            self.appName = bundleName
        }

        let manager = PacketTunnelManager(providerBundleIdentifier: "\(providerBundleIdentifier).XrayTunnel", groupIdentifier: groupIdentifier, appName: appName)
        self.packetTunnelManager = manager

        AutoDisconnectHelper.shared.configure(groupIdentifier: groupIdentifier, appName: appName)

        self.statusCancellable?.cancel()
        self.statusCancellable = manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleStatusChange()
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleStatusChange()
        }

        result(nil)
    }

    private func handleStatusChange() {
        guard let status = self.packetTunnelManager?.status else { return }

        let statusString: String
        switch status {
        case .connected:
            statusString = "CONNECTED"
            self.lastErrorMessage = ""
            if timer == nil {
                startTimer()
            }
            self.emitStatusEvent(status: statusString)
        case .connecting:
            statusString = "CONNECTING"
            self.lastErrorMessage = ""
            if timer == nil {
                startTimer()
            }
            self.emitStatusEvent(status: statusString)
        case .disconnecting:
            statusString = "DISCONNECTED"
            stopTimer()
            self.lastErrorMessage = ""
            self.emitStatusEvent(status: statusString)
        case .disconnected, .invalid:
            stopTimer()
            statusString = AutoDisconnectHelper.shared.checkAndHandleDisconnect(currentStatus: "DISCONNECTED")
            self.lastErrorMessage = ""
            self.emitStatusEvent(status: statusString)
        case .reasserting:
            statusString = "CONNECTING"
            self.lastErrorMessage = ""
            if timer == nil {
                startTimer()
            }
            self.emitStatusEvent(status: statusString)
        @unknown default:
            statusString = "ERROR"
            self.lastErrorMessage = "Unknown NEVPNStatus value"
            self.emitStatusEvent(status: statusString)
        }

        self.lastStatus = statusString
    }

    private func updateAutoDisconnectTime(call: FlutterMethodCall, result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.updateTime(call: call, packetTunnelManager: packetTunnelManager, result: result)
    }

    private func getRemainingAutoDisconnectTime(result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.getRemainingTime(packetTunnelManager: packetTunnelManager, result: result)
    }

    private func cancelAutoDisconnect(result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.cancel(packetTunnelManager: packetTunnelManager, result: result)
    }

    private func wasAutoDisconnected(result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.handleWasAutoDisconnected(result: result)
    }

    private func clearAutoDisconnectFlag(result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.handleClearFlag(result: result)
    }

    private func getAutoDisconnectTimestamp(result: @escaping FlutterResult) {
        AutoDisconnectHelper.shared.handleGetTimestamp(result: result)
    }
}
