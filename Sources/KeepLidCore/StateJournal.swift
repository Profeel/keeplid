import Foundation

public struct KeepLidState: Codable, Sendable {
    public var isActive: Bool
    public var startedAt: Date?
    public var expiresAt: Date?
    public var pid: Int32
    public var sleepDisabledByUs: Bool
    public var awdlDisabledByUs: Bool
    public var lidClosed: Bool
    public var wifiInterface: String
    public var lastPingMs: Double
    public var lastPingSuccess: Bool
    public var gatewayIP: String?
    public var batteryPercent: Int
    public var isCharging: Bool
    public var thermalState: String
    public var stopReason: String?

    public static let empty = KeepLidState(
        isActive: false,
        startedAt: nil,
        expiresAt: nil,
        pid: 0,
        sleepDisabledByUs: false,
        awdlDisabledByUs: false,
        lidClosed: false,
        wifiInterface: "en0",
        lastPingMs: 0.0,
        lastPingSuccess: false,
        gatewayIP: nil,
        batteryPercent: 100,
        isCharging: false,
        thermalState: "nominal",
        stopReason: nil
    )
    
    public static var stateFile: URL {
        return KeepLidConfig.configDir.appendingPathComponent("state.json")
    }
    
    public static func load() -> KeepLidState {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(KeepLidState.self, from: data) else {
            return .empty
        }
        return state
    }
    
    public func save() {
        try? FileManager.default.createDirectory(at: KeepLidConfig.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            let tempFile = KeepLidConfig.configDir.appendingPathComponent("state.json.tmp")
            try? data.write(to: tempFile)
            _ = try? FileManager.default.replaceItemAt(KeepLidState.stateFile, withItemAt: tempFile)
        }
    }
    
    public static func clear() {
        try? FileManager.default.removeItem(at: stateFile)
    }
}
