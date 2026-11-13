import Foundation
import IOKit.pwr_mgt

public final class PowerManager: @unchecked Sendable {
    public static let shared = PowerManager()
    
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var networkAssertionID: IOPMAssertionID = 0
    private let lock = NSLock()
    
    private init() {}
    
    @discardableResult
    public func setDisableSleep(_ disable: Bool) -> Bool {
        let flag = disable ? "1" : "0"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", flag]
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
    
    public func checkSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8) {
            for line in out.components(separatedBy: .newlines) {
                if line.contains("SleepDisabled") && line.contains("1") {
                    return true
                }
            }
        }
        return false
    }
    
    public func acquireAssertions() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        var success = true
        let name = "KeepLid Clamshell Wi-Fi Guard" as CFString
        
        if displayAssertionID == 0 {
            let ret = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name,
                &displayAssertionID
            )
            if ret != kIOReturnSuccess { success = false }
        }
        
        if systemAssertionID == 0 {
            let ret = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name,
                &systemAssertionID
            )
            if ret != kIOReturnSuccess { success = false }
        }
        
        if networkAssertionID == 0 {
            let ret = IOPMAssertionCreateWithName(
                "NetworkClientActive" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name,
                &networkAssertionID
            )
            if ret != kIOReturnSuccess { success = false }
        }
        
        return success
    }
    
    public func releaseAssertions() {
        lock.lock()
        defer { lock.unlock() }
        
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
        if networkAssertionID != 0 {
            IOPMAssertionRelease(networkAssertionID)
            networkAssertionID = 0
        }
    }
}
