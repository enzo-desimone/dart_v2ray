import Foundation

private enum RuntimeError: Error {
    case helperPathUnavailable
    case runtimeRootUnavailable
    case xrayBinaryMissing(String)
}

private func runtimeRoot(from helperPath: String) throws -> String {
    let helperURL = URL(fileURLWithPath: helperPath)
    let helpersURL = helperURL.deletingLastPathComponent()
    let contentsURL = helpersURL.deletingLastPathComponent()
    let runtimeURL = contentsURL.appendingPathComponent("Resources/dart_v2ray_runtime", isDirectory: true)
    let runtimePath = runtimeURL.path

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: runtimePath, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw RuntimeError.runtimeRootUnavailable
    }

    return runtimePath
}

private func resolveXrayPath(runtimeRoot: String) throws -> String {
    let xrayPath = URL(fileURLWithPath: runtimeRoot).appendingPathComponent("xray").path
    guard FileManager.default.isExecutableFile(atPath: xrayPath) else {
        throw RuntimeError.xrayBinaryMissing(xrayPath)
    }
    return xrayPath
}

private func launchXray() throws -> Never {
    guard let helperPath = Bundle.main.executablePath else {
        throw RuntimeError.helperPathUnavailable
    }

    let runtimeRoot = try runtimeRoot(from: helperPath)
    let xrayPath = try resolveXrayPath(runtimeRoot: runtimeRoot)

    setenv("XRAY_LOCATION_ASSET", runtimeRoot, 1)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: xrayPath)
    process.arguments = Array(CommandLine.arguments.dropFirst())
    process.currentDirectoryURL = URL(fileURLWithPath: runtimeRoot, isDirectory: true)
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
}

do {
    try launchXray()
} catch {
    fputs("dart_v2ray_runtime_helper error: \(error)\n", stderr)
    exit(2)
}
