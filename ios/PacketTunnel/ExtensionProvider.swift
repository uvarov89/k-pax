import Foundation
import Libbox
import NetworkExtension

// Base class for Packet Tunnel Provider
// Adapted from sing-box-for-apple for Flutter plugin
open class ExtensionProvider: NEPacketTunnelProvider {
    public var username: String?
    private var commandServer: LibboxCommandServer?
    private var platformInterface: ExtensionPlatformInterface?
    
    override open func startTunnel(options: [String: NSObject]?) async throws {
        do {
            try await startTunnelBody()
            FilePath.clearTunnelError()
        } catch {
            let text = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            FilePath.writeTunnelError(text)
            NSLog("PacketTunnel: start failed: \(text)")
            throw error
        }
    }

    private func startTunnelBody() async throws {
        if FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FilePath.groupName
        ) == nil {
            throw ExtensionStartupError(
                "(packet-tunnel) App Group unavailable: \(FilePath.groupName)"
            )
        }
        try FilePath.prepareSharedDirectories()

        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = FilePath.sharedDirectory.path
        setupOptions.workingPath = FilePath.workingDirectory.path
        setupOptions.tempPath = FilePath.cacheDirectory.path
        setupOptions.logMaxLines = 3000
        
        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError {
            throw ExtensionStartupError("(packet-tunnel) error: setup service: \(setupError.localizedDescription)")
        }
        
        var stderrError: NSError?
        LibboxRedirectStderr(
            FilePath.cacheDirectory.appendingPathComponent("stderr.log").path,
            &stderrError
        )
        if let stderrError {
            throw ExtensionStartupError("(packet-tunnel) redirect stderr error: \(stderrError.localizedDescription)")
        }
        
        await LibboxSetMemoryLimit(!SharedPreferences.ignoreMemoryLimit.getBlocking())
        
        if platformInterface == nil {
            platformInterface = ExtensionPlatformInterface(self)
        }
        
        guard let platformInterface = platformInterface else {
            throw ExtensionStartupError("(packet-tunnel): platformInterface is nil")
        }
        
        var error: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &error)
        if let error {
            throw ExtensionStartupError("(packet-tunnel): create command server error: \(error.localizedDescription)")
        }
        do {
            try commandServer?.start()
        } catch {
            throw ExtensionStartupError("(packet-tunnel): start command server error: \(error.localizedDescription)")
        }
        writeMessage("(packet-tunnel): Here I stand")
        try await startService()
    }
    
    func writeMessage(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(2, message: message)
        }
        NSLog("PacketTunnel: \(message)")
    }
    
    private func startService() async throws {
        let configContent: String
        if let fromFile = try? String(contentsOf: FilePath.tunnelConfigFile, encoding: .utf8),
           !fromFile.isEmpty {
            configContent = fromFile
        } else if let groupDefaults = UserDefaults(suiteName: FilePath.groupName),
                  let config = groupDefaults.string(forKey: "sing_box_current_config"),
                  !config.isEmpty {
            configContent = config
        } else if let activeConfig = ServerConfigManager().getActiveServerConfig(),
                  let configJson = activeConfig["config"] as? String,
                  !configJson.isEmpty {
            configContent = configJson
        } else {
            throw ExtensionStartupError(
                "(packet-tunnel) error: missing configuration (app group file empty)"
            )
        }
        
        let options = LibboxOverrideOptions()
        do {
            try commandServer?.startOrReloadService(configContent, options: options)
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: start service: \(error.localizedDescription)")
        }
    }
    
    func stopService() {
        do {
            try commandServer?.closeService()
        } catch {
            writeMessage("(packet-tunnel) error: stop service: \(error.localizedDescription)")
        }
        if let platformInterface {
            platformInterface.reset()
        }
    }
    
    func reloadService() async throws {
        writeMessage("(packet-tunnel) reloading service")
        reasserting = true
        defer {
            reasserting = false
        }
        try await startService()
    }
    
    override open func stopTunnel(with reason: NEProviderStopReason) async {
        // reason only — never log config or keys
        writeMessage("(packet-tunnel) stopping, reason=\(reason.rawValue) \(String(describing: reason))")
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
    }
    
    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        messageData
    }
    
    override open func sleep() async {
        if let commandServer {
            commandServer.pause()
        }
    }
    
    override open func wake() {
        if let commandServer {
            commandServer.wake()
        }
    }
}

