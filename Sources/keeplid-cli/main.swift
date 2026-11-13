import Foundation
import KeepLidCore

func parseDuration(_ str: String) -> Int? {
    let lower = str.lowercased().trimmingCharacters(in: .whitespaces)
    if lower == "infinite" || lower == "indefinite" || lower == "forever" || lower == "0" {
        return 0
    }
    
    var numStr = ""
    var unit = "m"
    for char in lower {
        if char.isNumber {
            numStr.append(char)
        } else {
            unit = String(char)
        }
    }
    
    guard let num = Int(numStr) else { return nil }
    switch unit {
    case "s": return num
    case "m": return num * 60
    case "h": return num * 3600
    case "d": return num * 86400
    default: return num * 60
    }
}

func printHelp() {
    print("""
    KeepLid (macOS Clamshell & Wi-Fi Guard)
    Keep your Mac running with lid closed and Wi-Fi rock solid.

    USAGE:
      keeplid start [duration]   Start keep-awake session (e.g. 30m, 2h, 4h, infinite)
      keeplid stop               Stop keep-awake and restore normal sleep
      keeplid status             Show current status and Wi-Fi health
      keeplid monitor            Interactive live terminal dashboard
      keeplid test-wifi          Run a 10-second Wi-Fi stability diagnostic
      keeplid help               Show this help message

    ALIASES:
      keeplid on [duration]      Same as 'keeplid start'
      keeplid off                Same as 'keeplid stop'
    """)
}

func printStatus() {
    let state = KeepLidState.load()
    let isKernelDisabled = PowerManager.shared.checkSleepDisabled()
    let clamshell = ClamshellObserver.shared.queryClamshellState()
    SafetyCircuitBreaker.shared.updateReadings()
    let battery = SafetyCircuitBreaker.shared.currentBatteryPercent
    let isCharging = SafetyCircuitBreaker.shared.isCharging
    let thermal = SafetyCircuitBreaker.shared.thermalStateString
    let gateway = WiFiGuard.shared.detectDefaultGateway() ?? "Unknown"
    
    print("\n═══════════════════════════════════════════════════════")
    print(" 🛡️  KeepLid Status")
    print("═══════════════════════════════════════════════════════")
    
    if state.isActive {
        print("  State:            \u{001B}[32m● ACTIVE\u{001B}[0m (PID: \(state.pid))")
        if let exp = state.expiresAt {
            let remain = max(0, Int(exp.timeIntervalSinceNow))
            let h = remain / 3600
            let m = (remain % 3600) / 60
            let s = remain % 60
            print("  Duration:         Expires in \(String(format: "%02d:%02d:%02d", h, m, s))")
        } else {
            print("  Duration:         Indefinite (until stopped)")
        }
    } else {
        print("  State:            \u{001B}[33m○ INACTIVE\u{001B}[0m (Normal macOS sleep policy)")
        if let reason = state.stopReason {
            print("  Last Stop Reason: \(reason)")
        }
    }
    
    print("  Kernel Clamshell: \(isKernelDisabled ? "\u{001B}[32mSleep Disabled (Safe to close lid)\u{001B}[0m" : "Normal Sleep Enabled")")
    print("  Lid State:        \(clamshell ? "Closed" : "Open")")
    print("  AWDL Boost:       \(state.awdlDisabledByUs ? "\u{001B}[32mActive (AirDrop paused for zero jitter)\u{001B}[0m" : "Standby")")
    
    print("───────────────────────────────────────────────────────")
    print("  Wi-Fi Gateway:    \(gateway)")
    if state.isActive {
        print("  Last Ping RTT:    \(String(format: "%.1f ms", state.lastPingMs)) (\(state.lastPingSuccess ? "Healthy" : "Failing"))")
    }
    print("  Battery:          \(battery)% (\(isCharging ? "Charging" : "On Battery"))")
    print("  Thermal Pressure: \(thermal.capitalized)")
    print("═══════════════════════════════════════════════════════\n")
}

func runMonitor() {
    print("\u{001B}[2J") // Clear screen
    while true {
        print("\u{001B}[H") // Cursor to top-left
        printStatus()
        print("  Press Ctrl+C to exit monitor (session continues running)")
        Thread.sleep(forTimeInterval: 1.0)
    }
}

func runWiFiTest() {
    print("\n[KeepLid] Starting 10-second Wi-Fi keep-alive diagnostic...")
    let guardInstance = WiFiGuard.shared
    let gw = guardInstance.detectDefaultGateway() ?? "223.5.5.5"
    print("Target Gateway / DNS: \(gw)")
    
    var count = 0
    var successes = 0
    var latencies: [Double] = []
    
    for i in 1...10 {
        guardInstance.performProbe()
        count += 1
        let ms = guardInstance.lastLatencyMs
        let ok = guardInstance.isConnected
        if ok {
            successes += 1
            latencies.append(ms)
            print("  [\(i)/10] Probe OK: \(String(format: "%.2f ms", ms))")
        } else {
            print("  [\(i)/10] Probe FAILED!")
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
    
    let avg = latencies.isEmpty ? 0.0 : latencies.reduce(0, +) / Double(latencies.count)
    let loss = Double(count - successes) / Double(count) * 100.0
    print("\nDiagnostic Summary:")
    print("  Probes Sent:    \(count)")
    print("  Successful:     \(successes)")
    print("  Packet Loss:    \(String(format: "%.1f%%", loss))")
    print("  Avg Latency:    \(String(format: "%.2f ms", avg))")
    if loss == 0.0 {
        print("  \u{001B}[32m✓ Wi-Fi connection and keep-alive are fully operational!\u{001B}[0m\n")
    } else {
        print("  \u{001B}[31m⚠️ Wi-Fi experienced packet drops. Auto-reconnection engine armed.\u{001B}[0m\n")
    }
}

// Main CLI router
let args = CommandLine.arguments

if args.count <= 1 {
    printStatus()
    print("Tip: Run 'keeplid start' to keep Mac awake on lid-close, or 'keeplid help' for commands.\n")
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "start", "on":
    var durationSeconds = 0
    if args.count >= 3 {
        if let parsed = parseDuration(args[2]) {
            durationSeconds = parsed
        } else {
            print("Error: Invalid duration '\(args[2])'. Use e.g. 30m, 2h, 4h, or infinite.")
            exit(1)
        }
    }
    
    print("\n🛡️  Starting KeepLid session...")
    if durationSeconds > 0 {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        print("  Duration set to: \(h > 0 ? "\(h)h " : "")\(m)m")
    } else {
        print("  Duration set to: Indefinite (until 'keeplid stop')")
    }
    
    if KeepLidEngine.shared.start(durationSeconds: durationSeconds) {
        print("  \u{001B}[32m✓ Clamshell sleep disabled (safe to close lid).\u{001B}[0m")
        print("  \u{001B}[32m✓ Display assertion held (prevents WiFiAgent display sleep drops).\u{001B}[0m")
        print("  \u{001B}[32m✓ Wi-Fi active heartbeat watchdog running.\u{001B}[0m")
        print("  \u{001B}[32m✓ Screen will auto-lock when lid closes (zero physical access risk).\u{001B}[0m")
        print("  \u{001B}[32m✓ Safety circuit breaker armed (battery floor 15%, thermal guard).\u{001B}[0m\n")
        print("KeepLid is now guarding this Mac in the background.")
        print("You can close the lid at any time. Wi-Fi and background tasks will remain running.\n")
        
        // If run with --foreground or in foreground mode, keep loop running
        if args.contains("--foreground") || args.contains("-f") {
            print("Running in foreground mode. Press Ctrl+C to stop.")
            while KeepLidEngine.shared.isRunning {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    } else {
        print("\u{001B}[31mFailed to start KeepLid. Please verify sudo permissions.\u{001B}[0m")
        exit(1)
    }

case "stop", "off":
    let current = KeepLidState.load()
    if current.isActive && current.pid > 0 && current.pid != ProcessInfo.processInfo.processIdentifier {
        // Signal the running process to stop gracefully
        kill(current.pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
    }
    KeepLidEngine.shared.stop(reason: "Stopped via CLI 'keeplid stop'")
    print("\n\u{001B}[32m✓ KeepLid stopped. Normal macOS sleep and Wi-Fi policies restored.\u{001B}[0m\n")

case "status":
    printStatus()

case "monitor":
    runMonitor()

case "test-wifi":
    runWiFiTest()

case "help", "--help", "-h":
    printHelp()

default:
    print("Unknown command: '\(command)'")
    printHelp()
    exit(1)
}
