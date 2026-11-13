import Foundation
import AppKit
import IOKit

public final class ClamshellObserver: @unchecked Sendable {
    public static let shared = ClamshellObserver()
    
    public private(set) var isLidClosed: Bool = false
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "com.keeplid.clamshell", qos: .userInitiated)
    
    public var onLidStateChange: ((Bool) -> Void)?
    
    private init() {
        self.isLidClosed = queryClamshellState()
    }
    
    public func queryClamshellState() -> Bool {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOPMrootDomain")
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        
        if let val = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return val
        }
        return false
    }
    
    public func hasExternalDisplay() -> Bool {
        let screens = NSScreen.screens
        return screens.contains { screen in
            let name = screen.localizedName
            return !name.contains("Built-in") && !name.contains("Color LCD")
        }
    }
    
    public func lockScreenImmediate() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY) else { return }
        defer { dlclose(handle) }
        
        typealias LockFunction = @convention(c) () -> Int32
        if let sym = dlsym(handle, "SACLockScreenImmediate") {
            let lockFn = unsafeBitCast(sym, to: LockFunction.self)
            _ = lockFn()
        }
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        isLidClosed = queryClamshellState()
        
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                let currentState = self.queryClamshellState()
                if currentState != self.isLidClosed {
                    self.isLidClosed = currentState
                    self.onLidStateChange?(currentState)
                }
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    
    public func stop() {
        isRunning = false
    }
}
