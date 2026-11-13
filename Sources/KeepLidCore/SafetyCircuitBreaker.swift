import Foundation
import IOKit.ps

public final class SafetyCircuitBreaker: @unchecked Sendable {
    public static let shared = SafetyCircuitBreaker()
    
    public private(set) var currentBatteryPercent: Int = 100
    public private(set) var isCharging: Bool = false
    public private(set) var isOnAC: Bool = true
    public private(set) var thermalStateString: String = "nominal"
    
    public var onSafetyTrip: ((String) -> Void)?
    
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "com.keeplid.safety", qos: .utility)
    
    private init() {
        updateReadings()
    }
    
    public func updateReadings() {
        if let (percent, charging, ac) = queryBattery() {
            self.currentBatteryPercent = percent
            self.isCharging = charging
            self.isOnAC = ac
        }
        
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: self.thermalStateString = "nominal"
        case .fair: self.thermalStateString = "fair"
        case .serious: self.thermalStateString = "serious"
        case .critical: self.thermalStateString = "critical"
        @unknown default: self.thermalStateString = "unknown"
        }
    }
    
    public func queryBattery() -> (percent: Int, isCharging: Bool, isAC: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let current = info[kIOPSCurrentCapacityKey as String] as? Int,
               let max = info[kIOPSMaxCapacityKey as String] as? Int,
               let isCharging = info[kIOPSIsChargingKey as String] as? Bool,
               let powerSource = info[kIOPSPowerSourceStateKey as String] as? String {
                let percent = max > 0 ? (current * 100) / max : 0
                let isAC = (powerSource == (kIOPSACPowerValue as String))
                return (percent, isCharging, isAC)
            }
        }
        return nil
    }
    
    public func start(config: KeepLidConfig, expiresAt: Date?) {
        guard !isRunning else { return }
        isRunning = true
        
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                self.updateReadings()
                
                // 1. Battery check
                if !self.isOnAC && !self.isCharging && self.currentBatteryPercent <= config.batteryFloor {
                    self.onSafetyTrip?("Battery reached safety floor (\(self.currentBatteryPercent)% <= \(config.batteryFloor)%)")
                    break
                }
                
                // 2. Thermal check
                if config.thermalProtection && ProcessInfo.processInfo.thermalState == .critical {
                    self.onSafetyTrip?("Thermal state critical. Safeguarding Mac against overheating.")
                    break
                }
                
                // 3. Timer check
                if let expiry = expiresAt, Date() >= expiry {
                    self.onSafetyTrip?("Session timer expired.")
                    break
                }
                
                Thread.sleep(forTimeInterval: 5.0)
            }
        }
    }
    
    public func stop() {
        isRunning = false
    }
}
