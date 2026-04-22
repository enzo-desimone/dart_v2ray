import Cocoa
import FlutterMacOS
import LibXray

public class DartV2rayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  private var providerBundleIdentifier: String?
  private var groupIdentifier: String?
  private var appName: String = "VPN"

  private var isRunning: Bool = false
  private var lastStatus: String = "DISCONNECTED"
  private var lastErrorMessage: String = ""

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "dart_v2ray",
      binaryMessenger: registrar.messenger
    )

    let eventChannel = FlutterEventChannel(
      name: "dart_v2ray/status",
      binaryMessenger: registrar.messenger
    )

    let instance = DartV2rayPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    emitStatusEvent()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initializeVless":
      initializeVless(call: call, result: result)

    case "requestPermission":
      requestPermission(result: result)

    case "startVless":
      startVless(call: call, result: result)

    case "stopVless":
      stopVless(result: result)

    case "getCoreVersion":
      getCoreVersion(result: result)

    case "getServerDelay":
      getServerDelay(call: call, result: result)

    case "getConnectedServerDelay":
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "getConnectedServerDelay is not implemented on macOS yet.",
        details: nil
      ))

    case "updateAutoDisconnectTime",
         "getRemainingAutoDisconnectTime",
         "cancelAutoDisconnect",
         "wasAutoDisconnected",
         "clearAutoDisconnectFlag",
         "getAutoDisconnectTimestamp":
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "\(call.method) is not implemented on macOS yet.",
        details: nil
      ))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initializeVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Missing arguments.",
        details: nil
      ))
      return
    }

    self.providerBundleIdentifier = arguments["providerBundleIdentifier"] as? String
    self.groupIdentifier = arguments["groupIdentifier"] as? String

    if let customAppName = arguments["appName"] as? String, !customAppName.isEmpty {
      self.appName = customAppName
    } else if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
      self.appName = displayName
    } else if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
      self.appName = bundleName
    }

    guard let groupIdentifier = self.groupIdentifier, !groupIdentifier.isEmpty else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "groupIdentifier is required.",
        details: nil
      ))
      return
    }

    // providerBundleIdentifier per ora può anche restare opzionale su macOS
    _ = groupIdentifier

    result(nil)
  }

  private func requestPermission(result: @escaping FlutterResult) {
    result(true)
  }

  private func startVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let _ = arguments["remark"] as? String,
          let config = arguments["config"] as? String,
          !config.isEmpty else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Invalid arguments for startVless.",
        details: nil
      ))
      return
    }

    let requireTun = arguments["requireTun"] as? Bool ?? false
    if requireTun {
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "macOS TUN/NetworkExtension is not implemented yet.",
        details: nil
      ))
      return
    }

    do {
      // TODO: sostituisci con l'avvio reale del core LibXray
      // Esempio:
      // try XrayCoreBridge.start(config: config)

      self.isRunning = true
      self.lastStatus = "CONNECTED"
      self.lastErrorMessage = ""
      emitStatusEvent()
      result(nil)
    } catch {
      self.isRunning = false
      self.lastStatus = "DISCONNECTED"
      self.lastErrorMessage = error.localizedDescription
      emitStatusEvent()

      result(FlutterError(
        code: "XRAY_START_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func stopVless(result: @escaping FlutterResult) {
    do {
      // TODO: sostituisci con lo stop reale del core LibXray
      // Esempio:
      // try XrayCoreBridge.stop()

      self.isRunning = false
      self.lastStatus = "DISCONNECTED"
      self.lastErrorMessage = ""
      emitStatusEvent()
      result(nil)
    } catch {
      self.lastErrorMessage = error.localizedDescription
      emitStatusEvent()

      result(FlutterError(
        code: "XRAY_STOP_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func getCoreVersion(result: @escaping FlutterResult) {
    // Sostituisci col simbolo reale esportato dal framework
    let raw = String(cString: CGoXrayVersion())
    result(raw)
  }

  private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let url = arguments["url"] as? String,
          let config = arguments["config"] as? String,
          !url.isEmpty,
          !config.isEmpty else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Invalid arguments for getServerDelay.",
        details: nil
      ))
      return
    }

    Task.detached {
      var error: NSError?
      var delay: Int64 = -1

      // Sostituisci col simbolo reale esportato dal framework
      XRayMeasureOutboundDelay(config, url, &delay, &error)

      await MainActor.run {
        if let error {
          result(FlutterError(
            code: "XRAY_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(delay)
        }
      }
    }
  }

  private func emitStatusEvent() {
    guard let eventSink else { return }

    let payload: [Any] = [
      "0",
      "0",
      "0",
      "0",
      "0",
      lastStatus,
      NSNull(),
      lastStatus,
      "proxy",
      "",
      lastErrorMessage,
      isRunning ? "true" : "false"
    ]

    eventSink(payload)
  }
}