import Foundation
import NetworkExtension
import Combine

final class PacketTunnelManager: ObservableObject {
    var providerBundleIdentifier: String?
    var groupIdentifier: String?
    var appName: String = "VPN"
    var remark: String = "Xray"
    var xrayConfig: Data = "".data(using: .utf8)!
    var dnsServers: [String]?
    var autoDisconnect: [String: Any]?

    private var cancellables: Set<AnyCancellable> = []

    @Published private var manager: NETunnelProviderManager?
    @Published private(set) var isProcessing: Bool = false

    var status: NEVPNStatus? {
        manager.flatMap { $0.connection.status }
    }

    var connectedDate: Date? {
        manager.flatMap { $0.connection.connectedDate }
    }

    init(providerBundleIdentifier: String, groupIdentifier: String, appName: String = "VPN") {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.groupIdentifier = groupIdentifier
        self.appName = appName
        isProcessing = true
        Task(priority: .userInitiated) {
            await self.reload()
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    func reload() async {
        self.cancellables.removeAll()
        self.manager = await self.loadTunnelProviderManager()
        NotificationCenter.default
            .publisher(for: .NEVPNConfigurationChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                Task(priority: .high) {
                    self.manager = await self.loadTunnelProviderManager()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in objectWillChange.send() }
            .store(in: &cancellables)
    }

    func saveToPreferences() async throws {
        guard let providerBundleIdentifier = providerBundleIdentifier else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider bundle identifier is missing."])
        }

        do {
            let allManagers = try await NETunnelProviderManager.loadAllFromPreferences()
            let existingManager = allManagers.first(where: {
                guard let configuration = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return configuration.providerBundleIdentifier == providerBundleIdentifier
            })

            let manager = existingManager ?? self.manager ?? NETunnelProviderManager()
            manager.localizedDescription = appName
            manager.protocolConfiguration = {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = providerBundleIdentifier
                configuration.serverAddress = "Xray"

                var config: [String: Any] = [
                    "xrayConfig": xrayConfig,
                    "dnsServers": dnsServers ?? [],
                    "groupIdentifier": groupIdentifier ?? ""
                ]

                if let autoDisconnect = autoDisconnect {
                    config["autoDisconnect"] = autoDisconnect
                }

                configuration.providerConfiguration = config
                return configuration
            }()
            manager.isEnabled = true
            try await manager.saveToPreferences()

            await self.reload()
        } catch {
            print("Error saving VPN preferences: \(error.localizedDescription)")
            throw error
        }
    }

    func start() async throws {
        guard let manager = manager else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager not found"])
        }

        if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
        }

        do {
            try manager.connection.startVPNTunnel()
        } catch {
            print("Failed to start VPN tunnel: \(error.localizedDescription)")
            throw error
        }
    }

    func stop() {
        guard let manager = manager else {
            return
        }
        manager.connection.stopVPNTunnel()
    }

    @discardableResult
    func sendProviderMessage(data: Data) async throws -> Data? {
        guard let manager = manager else {
            return nil
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid connection type"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { response in
                    continuation.resume(with: .success(response))
                }
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }

    func testSaveAndLoadProfile() async -> Bool {
        do {
            try await saveToPreferences()
            let _ = await loadTunnelProviderManager()
            return true
        } catch {
            print("Error during save and load test: \(error.localizedDescription)")
            return false
        }
    }

    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            guard let reval = managers.first(where: {
                guard let configuration = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return configuration.providerBundleIdentifier == providerBundleIdentifier
            }) else {
                return nil
            }

            try await reval.loadFromPreferences()
            return reval
        } catch {
            print("Error loading tunnel provider manager: \(error.localizedDescription)")
            return nil
        }
    }
}
