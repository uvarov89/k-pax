import Foundation
import Combine
import Libbox
import NetworkExtension

// Extension Profile for managing VPN connection
// Adapted from sing-box-for-apple for Flutter plugin
public class ExtensionProfile: ObservableObject {
    public static let controlKind = "com.qusadprod.sing_box.widget.ServiceToggle"
    
    private let manager: NEVPNManager
    private var connection: NEVPNConnection
    private var observer: Any?
    
    @Published public var status: NEVPNStatus
    @Published public var connectedDate: Date?
    
    public init(_ manager: NEVPNManager) {
        self.manager = manager
        connection = manager.connection
        status = manager.connection.status
        connectedDate = manager.connection.connectedDate
    }
    
    public func register() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }
            guard let connection = notification.object as? NEVPNConnection else {
                NSLog("ExtensionProfile: notification.object is not NEVPNConnection")
                return
            }
            self.connection = connection
            self.status = connection.status
            self.connectedDate = connection.connectedDate
        }
    }
    
    private func unregister() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setOnDemandRules() {
        var rules: [NEOnDemandRule] = []
        if SharedPreferences.alwaysOn.getBlocking() {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            rules.append(rule)
        } else {
            if SharedPreferences.autoConnectWifi.getBlocking() {
                let rule = NEOnDemandRuleConnect()
                rule.interfaceTypeMatch = .wiFi
                rules.append(rule)
            }
            if SharedPreferences.autoConnectCellular.getBlocking() {
                let rule = NEOnDemandRuleConnect()
                rule.interfaceTypeMatch = .cellular
                rules.append(rule)
            }
        }
        let fallback = NEOnDemandRuleIgnore()
        fallback.interfaceTypeMatch = .any
        rules.append(fallback)
        manager.onDemandRules = rules
        manager.isOnDemandEnabled = rules.count > 1
    }

    public static func configureOnDemand(wifi: Bool, cellular: Bool) async throws {
        let oldWifi = SharedPreferences.autoConnectWifi.getBlocking()
        let oldCellular = SharedPreferences.autoConnectCellular.getBlocking()
        let oldAlwaysOn = SharedPreferences.alwaysOn.getBlocking()
        SharedPreferences.autoConnectWifi.set(wifi)
        SharedPreferences.autoConnectCellular.set(cellular)
        // Both network types means automatic reconnection on any network.
        // This is user-controlled On Demand, not supervised-device Always On VPN.
        SharedPreferences.alwaysOn.set(wifi && cellular)
        do {
            if let profile = try await load() {
                profile.setOnDemandRules()
                let defaults = UserDefaults(suiteName: FilePath.groupName)
                if defaults?.string(forKey: "sing_box_current_config")?.isEmpty != false {
                    profile.manager.isOnDemandEnabled = false
                }
                try await profile.manager.saveToPreferences()
                try await profile.manager.loadFromPreferences()
            }
        } catch {
            SharedPreferences.autoConnectWifi.set(oldWifi)
            SharedPreferences.autoConnectCellular.set(oldCellular)
            SharedPreferences.alwaysOn.set(oldAlwaysOn)
            throw error
        }
    }

    public func updateAlwaysOn(_ newState: Bool) async throws {
        try await Self.configureOnDemand(wifi: newState, cellular: newState)
    }

    @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
    public func fetchLastDisconnectError() async throws {
        try await connection.fetchLastDisconnectError()
    }
    
    private static var preferredDisplayName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "VPN"
    }

    public func start() async throws {
        await fetchProfile()
        manager.isEnabled = true
        manager.localizedDescription = Self.preferredDisplayName
        setOnDemandRules()
        #if !os(tvOS)
            if let protocolConfiguration = manager.protocolConfiguration {
                let includeAllNetworks = SharedPreferences.includeAllNetworks.getBlocking()
                protocolConfiguration.includeAllNetworks = includeAllNetworks
                if #available(iOS 16.4, macOS 13.3, *) {
                    protocolConfiguration.excludeCellularServices = !includeAllNetworks
                }
            }
        #endif
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()
    }
    
    public func fetchProfile() async {
        // Keep config already written by SingBoxPlugin.connect(); only fill from
        // ServerConfigManager when App Group has nothing yet.
        let groupDefaults = UserDefaults(suiteName: FilePath.groupName)
        if let existing = groupDefaults?.string(forKey: "sing_box_current_config"),
           !existing.isEmpty {
            return
        }
        let serverConfigManager = ServerConfigManager()
        if let activeConfig = serverConfigManager.getActiveServerConfig() {
            if let configJson = activeConfig["config"] as? String {
                groupDefaults?.set(configJson, forKey: "sing_box_current_config")
            } else if let configData = try? JSONSerialization.data(withJSONObject: activeConfig),
                      let configJson = String(data: configData, encoding: .utf8) {
                groupDefaults?.set(configJson, forKey: "sing_box_current_config")
            }
        }
    }
    
    public func stop() async throws {
        // Settings may have updated this profile through another manager instance.
        try await manager.loadFromPreferences()
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try await manager.saveToPreferences()
        }
        do {
            if let client = LibboxNewStandaloneCommandClient() {
                try client.serviceClose()
            }
        } catch {
            NSLog("ExtensionProfile: Error closing service: \(error.localizedDescription)")
        }
        manager.connection.stopVPNTunnel()
    }
    
    public func restart() async throws {
        try await stop()
        var waitSeconds = 0
        while await MainActor.run(body: { status }) != .disconnected {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC)
            waitSeconds += 1
            if waitSeconds >= 5 {
                throw NSError(domain: "Restart service timeout", code: 0)
            }
        }
        try await start()
    }
    
    public static func load() async throws -> ExtensionProfile? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "\(FilePath.packageName).extension"
        }) else { return nil }
        let profile = ExtensionProfile(manager)
        return profile
    }
    
    public static func install() async throws {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = preferredDisplayName
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "\(FilePath.packageName).extension"
        tunnelProtocol.serverAddress = "sing-box"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }
}

