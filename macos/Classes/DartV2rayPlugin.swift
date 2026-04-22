import Cocoa
import FlutterMacOS
import LibXray

public class DartV2rayPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dart_v2ray", binaryMessenger: registrar.messenger)
    let instance = DartV2rayPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCoreVersion":
      let raw = String(cString: CGoXrayVersion())
      result(raw)

    case "requestPermission":
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}