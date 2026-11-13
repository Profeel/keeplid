import Foundation

public struct KeepLidConfig: Codable, Sendable {
    public var heartbeatInterval: Double
    public var pingTargets: [String]
    public var enableAWDLBoost: Bool
    public var enableScreenLock: Bool
    public var batteryFloor: Int
    public var thermalProtection: Bool
    public var defaultDurationSeconds: Int
    
    public static let `default` = KeepLidConfig(
        heartbeatInterval: 3.0,
        pingTargets: ["gateway", "223.5.5.5", "1.1.1.1"],
        enableAWDLBoost: true,
        enableScreenLock: true,
        batteryFloor: 15,
        thermalProtection: true,
        defaultDurationSeconds: 0 // 0 means indefinite until stopped
    )
    
    public static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".keeplid", isDirectory: true)
    }
    
    public static var configFile: URL {
        return configDir.appendingPathComponent("config.json")
    }
    
    public static func load() -> KeepLidConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(KeepLidConfig.self, from: data) else {
            return .default
        }
        return config
    }
    
    public func save() {
        try? FileManager.default.createDirectory(at: KeepLidConfig.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: KeepLidConfig.configFile)
        }
    }
}
