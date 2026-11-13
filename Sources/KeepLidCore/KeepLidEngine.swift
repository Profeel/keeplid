import Foundation

public final class KeepLidEngine: @unchecked Sendable {
    public static let shared = KeepLidEngine()
    
    public private(set) var config: KeepLidConfig
    public private(set) var state: KeepLidState
    public private(set) var isRunning: Bool = false
    
    private var stateSyncTimer: Timer?
    private let queue = DispatchQueue(label: "com.keeplid.engine")
    
    public var onStateChange: ((KeepLidState) -> Void)?
    
    private init() {
        self.config = KeepLidConfig.load()
        self.state = KeepLidState.load()
    }
    
    public func start(durationSeconds: Int? = nil) -> Bool {
        guard !isRunning else { return true }
        
        // 1. Recover if previously dirty
        recoverIfDirty()
        
        // 2. Determine expiration
        let duration = durationSeconds ?? config.defaultDurationSeconds
        let now = Date()
        let expiresAt = duration > 0 ? now.addingTimeInterval(Double(duration)) : nil
        
        // 3. Enable kernel sleep disable
        guard PowerManager.shared.setDisableSleep(true) else {
            print("Error: Could not disable sleep via pmset. Check sudo permissions.")
            return false
        }
        
        // 4. Acquire IOKit assertions
        _ = PowerManager.shared.acquireAssertions()
        
        // 5. Start Wi-Fi Guard
        WiFiGuard.shared.start(interval: config.heartbeatInterval)
        
        // 6. Start Clamshell Observer
        ClamshellObserver.shared.onLidStateChange = { [weak self] isClosed in
            guard let self = self else { return }
            self.handleLidStateChange(isClosed)
        }
        ClamshellObserver.shared.start()
        
        // Handle immediate lid state
        if ClamshellObserver.shared.isLidClosed {
            handleLidStateChange(true)
        }
        
        // 7. Start Safety Circuit Breaker
        SafetyCircuitBreaker.shared.onSafetyTrip = { [weak self] reason in
            print("\n[KeepLid Safety Trip] \(reason)")
            self?.stop(reason: reason)
        }
        SafetyCircuitBreaker.shared.start(config: config, expiresAt: expiresAt)
        
        // 8. Update state
        isRunning = true
        state.isActive = true
        state.startedAt = now
        state.expiresAt = expiresAt
        state.pid = ProcessInfo.processInfo.processIdentifier
        state.sleepDisabledByUs = true
        state.awdlDisabledByUs = false
        state.lidClosed = ClamshellObserver.shared.isLidClosed
        state.wifiInterface = WiFiGuard.shared.interface
        state.stopReason = nil
        syncStateNow()
        
        // 9. Periodic state file sync
        startStateSyncLoop()
        
        // 10. Install signal traps
        installSignalTraps()
        
        onStateChange?(state)
        return true
    }
    
    public func stop(reason: String = "Stopped by user") {
        guard isRunning else { return }
        isRunning = false
        
        // 1. Restore normal sleep
        PowerManager.shared.releaseAssertions()
        PowerManager.shared.setDisableSleep(false)
        
        // 2. Restore AWDL if altered
        if state.awdlDisabledByUs {
            WiFiGuard.shared.setAWDLDown(false)
            state.awdlDisabledByUs = false
        }
        
        // 3. Stop sub-components
        WiFiGuard.shared.stop()
        ClamshellObserver.shared.stop()
        SafetyCircuitBreaker.shared.stop()
        
        // 4. Update state journal
        state.isActive = false
        state.stopReason = reason
        state.sleepDisabledByUs = false
        syncStateNow()
        
        onStateChange?(state)
    }
    
    private func handleLidStateChange(_ isClosed: Bool) {
        state.lidClosed = isClosed
        
        if isClosed {
            // Lid was closed!
            // 1. Lock screen if enabled and no external monitor
            if config.enableScreenLock && !ClamshellObserver.shared.hasExternalDisplay() {
                ClamshellObserver.shared.lockScreenImmediate()
            }
            
            // 2. AWDL boost
            if config.enableAWDLBoost {
                if WiFiGuard.shared.setAWDLDown(true) {
                    state.awdlDisabledByUs = true
                }
            }
            
            // 3. Immediately send keepalive probe to maintain Wi-Fi active link
            WiFiGuard.shared.performProbe()
        } else {
            // Lid was opened!
            if state.awdlDisabledByUs {
                WiFiGuard.shared.setAWDLDown(false)
                state.awdlDisabledByUs = false
            }
        }
        
        syncStateNow()
        onStateChange?(state)
    }
    
    public func syncStateNow() {
        SafetyCircuitBreaker.shared.updateReadings()
        state.batteryPercent = SafetyCircuitBreaker.shared.currentBatteryPercent
        state.isCharging = SafetyCircuitBreaker.shared.isCharging
        state.thermalState = SafetyCircuitBreaker.shared.thermalStateString
        state.lastPingMs = WiFiGuard.shared.lastLatencyMs
        state.lastPingSuccess = WiFiGuard.shared.isConnected
        state.gatewayIP = WiFiGuard.shared.gatewayIP
        state.save()
    }
    
    private func startStateSyncLoop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                self.syncStateNow()
                self.onStateChange?(self.state)
                Thread.sleep(forTimeInterval: 2.0)
            }
        }
    }
    
    public func recoverIfDirty() {
        let loaded = KeepLidState.load()
        if loaded.sleepDisabledByUs {
            // Previous run didn't exit cleanly!
            // Check if process is still running
            if loaded.pid > 0 && loaded.pid != ProcessInfo.processInfo.processIdentifier {
                let killRet = kill(loaded.pid, 0)
                if killRet != 0 {
                    // Stale process is gone, clean up
                    PowerManager.shared.setDisableSleep(false)
                    WiFiGuard.shared.setAWDLDown(false)
                    var cleaned = loaded
                    cleaned.isActive = false
                    cleaned.sleepDisabledByUs = false
                    cleaned.awdlDisabledByUs = false
                    cleaned.stopReason = "Recovered from prior unclosed session"
                    cleaned.save()
                }
            }
        }
    }
    
    private func installSignalTraps() {
        let signalHandler: @convention(c) (Int32) -> Void = { sig in
            print("\nCaught signal \(sig), safely restoring macOS power settings...")
            KeepLidEngine.shared.stop(reason: "Signal \(sig) received")
            exit(0)
        }
        signal(SIGINT, signalHandler)
        signal(SIGTERM, signalHandler)
        signal(SIGHUP, signalHandler)
    }
}
