import Foundation

final class XrayBridge {
  enum BridgeError: LocalizedError {
    case startFailed(code: Int32, message: String)

    var errorDescription: String? {
      switch self {
      case .startFailed(let code, let message):
        return "Xray bridge start failed (code=\(code)): \(message)"
      }
    }
  }

  func start(configPath: String) throws {
    let code = configPath.withCString { cPath in
      XrayStartFromConfigPath(cPath)
    }
    guard code == 0 else {
      throw BridgeError.startFailed(code: code, message: Self.lastError())
    }
  }

  func start(configJson: String) throws {
    let code = configJson.withCString { cJson in
      XrayStartFromConfigJson(cJson)
    }
    guard code == 0 else {
      throw BridgeError.startFailed(code: code, message: Self.lastError())
    }
  }

  func stop() {
    _ = XrayStop()
  }

  func version() -> String {
    guard let cVersion = XrayVersion() else {
      return "xray-unavailable"
    }
    defer { XrayFreeString(cVersion) }
    return String(cString: cVersion)
  }

  static func lastError() -> String {
    guard let cError = XrayLastError() else {
      return "unknown error"
    }
    defer { XrayFreeString(cError) }
    let error = String(cString: cError)
    return error.isEmpty ? "unknown error" : error
  }
}
