import Foundation

public enum FilePath {
    /// App bundle id (strips `.extension` / `.RunnerTests` when running inside those targets).
    public static var packageName: String {
        let id = Bundle.main.bundleIdentifier ?? "space.kpax.app"
        for suffix in [".extension", ".RunnerTests"] where id.hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }
}

public extension FilePath {
    static var groupName: String { "group.\(packageName)" }

    private static var defaultSharedDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)
    }
    
    #if os(iOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                // Fallback to standard directory if App Groups not configured
                guard let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    // Last fallback - temporary directory
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and documentDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
        }
    #elseif os(tvOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                guard let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and cachesDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #elseif os(macOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                guard let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and applicationSupportDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
        }
    #endif
    
    #if os(iOS)
        static let cacheDirectory = sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(tvOS)
        static let cacheDirectory = sharedDirectory
    #elseif os(macOS)
        static var cacheDirectory: URL {
            sharedDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #endif
    
    #if os(macOS)
        static var workingDirectory: URL {
            cacheDirectory.appendingPathComponent("Working", isDirectory: true)
        }
    #else
        static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
    #endif

    static var tunnelConfigFile: URL {
        sharedDirectory.appendingPathComponent("sing_box_current_config.json", isDirectory: false)
    }

    static var tunnelLastErrorFile: URL {
        sharedDirectory.appendingPathComponent("packet_tunnel_last_error.txt", isDirectory: false)
    }

    static func prepareSharedDirectories() throws {
        let fm = FileManager.default
        for dir in [sharedDirectory, cacheDirectory, workingDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func writeTunnelConfig(_ config: String) throws {
        try prepareSharedDirectories()
        guard let data = config.data(using: .utf8) else {
            throw NSError(domain: "FilePath", code: 1, userInfo: [NSLocalizedDescriptionKey: "config utf8 failed"])
        }
        try data.write(to: tunnelConfigFile, options: .atomic)
        if let groupDefaults = UserDefaults(suiteName: groupName) {
            groupDefaults.set(config, forKey: "sing_box_current_config")
        }
    }

    static func readTunnelConfig() -> String? {
        if let data = try? Data(contentsOf: tunnelConfigFile),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        if let groupDefaults = UserDefaults(suiteName: groupName),
           let text = groupDefaults.string(forKey: "sing_box_current_config"),
           !text.isEmpty {
            return text
        }
        return UserDefaults.standard.string(forKey: "sing_box_current_config")
    }

    static func clearTunnelConfig() {
        try? FileManager.default.removeItem(at: tunnelConfigFile)
        UserDefaults(suiteName: groupName)?.removeObject(forKey: "sing_box_current_config")
        UserDefaults.standard.removeObject(forKey: "sing_box_current_config")
    }

    static func writeTunnelError(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? prepareSharedDirectories()
        try? text.data(using: .utf8)?.write(to: tunnelLastErrorFile, options: .atomic)
        UserDefaults(suiteName: groupName)?.set(text, forKey: "packet_tunnel_last_error")
    }

    static func readTunnelError() -> String? {
        if let data = try? Data(contentsOf: tunnelLastErrorFile),
           let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return UserDefaults(suiteName: groupName)?
            .string(forKey: "packet_tunnel_last_error")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clearTunnelError() {
        try? FileManager.default.removeItem(at: tunnelLastErrorFile)
        UserDefaults(suiteName: groupName)?.removeObject(forKey: "packet_tunnel_last_error")
    }
    
    static var iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true) ?? URL(string: "stub")!
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
    
    var relativePath: String {
        path
    }
}

