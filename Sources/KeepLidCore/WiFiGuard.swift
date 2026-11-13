import Foundation

public final class WiFiGuard: @unchecked Sendable {
    public static let shared = WiFiGuard()
    
    public var interface: String = "en0"
    public private(set) var gatewayIP: String?
    public private(set) var lastLatencyMs: Double = 0.0
    public private(set) var isConnected: Bool = false
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var totalProbes: Int = 0
    public private(set) var successfulProbes: Int = 0
    
    private var heartbeatTimer: Timer?
    private let queue = DispatchQueue(label: "com.keeplid.wifiguard", qos: .utility)
    private var isRunning: Bool = false
    private var onStatusUpdate: ((Double, Bool) -> Void)?
    
    private init() {
        self.gatewayIP = detectDefaultGateway()
    }
    
    public func setUpdateHandler(_ handler: @escaping (Double, Bool) -> Void) {
        self.onStatusUpdate = handler
    }
    
    public func detectDefaultGateway() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    public func start(interval: Double = 3.0) {
        guard !isRunning else { return }
        isRunning = true
        consecutiveFailures = 0
        totalProbes = 0
        successfulProbes = 0
        
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                self.performProbe()
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }
    
    public func stop() {
        isRunning = false
    }
    
    public func performProbe() {
        totalProbes += 1
        let target = gatewayIP ?? detectDefaultGateway() ?? "223.5.5.5"
        self.gatewayIP = target
        
        let (success, latency) = ping(host: target, timeoutMs: 1000)
        
        if success {
            consecutiveFailures = 0
            successfulProbes += 1
            lastLatencyMs = latency
            isConnected = true
        } else {
            // Fallback probe to public DNS to distinguish router unreachable from total network down
            let (dnsSuccess, dnsLatency) = ping(host: "223.5.5.5", timeoutMs: 1000)
            if dnsSuccess {
                consecutiveFailures = 0
                successfulProbes += 1
                lastLatencyMs = dnsLatency
                isConnected = true
            } else {
                consecutiveFailures += 1
                isConnected = false
                handleOutage()
            }
        }
        
        onStatusUpdate?(lastLatencyMs, isConnected)
    }
    
    private func ping(host: String, timeoutMs: Int) -> (Bool, Double) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return (false, 0.0)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Example line: "64 bytes from 192.168.0.1: icmp_seq=0 ttl=64 time=3.630 ms"
                if let timeRange = output.range(of: "time=") {
                    let sub = output[timeRange.upperBound...]
                    if let msRange = sub.range(of: " ms") {
                        let msStr = sub[..<msRange.lowerBound].trimmingCharacters(in: .whitespaces)
                        if let ms = Double(msStr) {
                            return (true, ms)
                        }
                    }
                }
                return (true, 1.0)
            }
        } catch {
            return (false, 0.0)
        }
        return (false, 0.0)
    }
    
    private func handleOutage() {
        // Self-healing watchdog:
        // If 2 failures (approx 6 seconds): ensure Wi-Fi power is On
        if consecutiveFailures == 2 {
            ensureWiFiPowerOn()
        }
        // If 4 failures (approx 12 seconds): cycle Wi-Fi power to clear driver hang and trigger auto-rejoin
        else if consecutiveFailures == 4 {
            cycleWiFiPower()
        }
    }
    
    @discardableResult
    public func ensureWiFiPowerOn() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-setairportpower", interface, "on"]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
    
    @discardableResult
    public func cycleWiFiPower() -> Bool {
        let off = Process()
        off.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        off.arguments = ["-setairportpower", interface, "off"]
        try? off.run()
        off.waitUntilExit()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        let on = Process()
        on.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        on.arguments = ["-setairportpower", interface, "on"]
        try? on.run()
        on.waitUntilExit()
        
        return on.terminationStatus == 0
    }
    
    @discardableResult
    public func setAWDLDown(_ down: Bool) -> Bool {
        let action = down ? "down" : "up"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/sbin/ifconfig", "awdl0", action]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
