import SwiftUI
import KeepLidCore

public final class DashboardViewModel: ObservableObject, @unchecked Sendable {
    @Published public var isActive: Bool = false
    @Published public var isLidClosed: Bool = false
    @Published public var wifiLatencyMs: Double = 0.0
    @Published public var wifiConnected: Bool = false
    @Published public var gatewayIP: String = "Detecting..."
    @Published public var batteryPercent: Int = 100
    @Published public var isCharging: Bool = false
    @Published public var thermalState: String = "nominal"
    @Published public var timeRemainingStr: String = ""
    @Published public var selectedDuration: Int = 0 // 0 = indefinite
    
    // Toggles
    @Published public var enableAWDLBoost: Bool = true
    @Published public var enableScreenLock: Bool = true
    @Published public var heartbeatInterval: Double = 3.0
    
    private var timer: Timer?
    private let engine = KeepLidEngine.shared
    
    public init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }
    
    public func refresh() {
        let state = KeepLidState.load()
        self.isActive = engine.isRunning || state.isActive
        self.isLidClosed = ClamshellObserver.shared.queryClamshellState()
        self.wifiLatencyMs = WiFiGuard.shared.lastLatencyMs
        self.wifiConnected = WiFiGuard.shared.isConnected
        self.gatewayIP = WiFiGuard.shared.gatewayIP ?? WiFiGuard.shared.detectDefaultGateway() ?? "192.168.0.1"
        
        SafetyCircuitBreaker.shared.updateReadings()
        self.batteryPercent = SafetyCircuitBreaker.shared.currentBatteryPercent
        self.isCharging = SafetyCircuitBreaker.shared.isCharging
        self.thermalState = SafetyCircuitBreaker.shared.thermalStateString
        
        if let exp = state.expiresAt, state.isActive {
            let remain = max(0, Int(exp.timeIntervalSinceNow))
            let h = remain / 3600
            let m = (remain % 3600) / 60
            let s = remain % 60
            self.timeRemainingStr = String(format: "%02d:%02d:%02d", h, m, s)
        } else if state.isActive {
            self.timeRemainingStr = "无限期运行"
        } else {
            self.timeRemainingStr = "已停止"
        }
        
        self.enableAWDLBoost = engine.config.enableAWDLBoost
        self.enableScreenLock = engine.config.enableScreenLock
    }
    
    public func toggleKeepAwake() {
        if isActive {
            engine.stop(reason: "用户点击停止保活")
        } else {
            _ = engine.start(durationSeconds: selectedDuration)
        }
        refresh()
    }
    
    public func startWithDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        _ = engine.start(durationSeconds: seconds)
        refresh()
    }
    
    public func runWiFiDiagnostics(completion: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global().async {
            WiFiGuard.shared.performProbe()
            let ms = WiFiGuard.shared.lastLatencyMs
            let ok = WiFiGuard.shared.isConnected
            let target = WiFiGuard.shared.gatewayIP ?? "网关"
            let msg = ok
                ? "✓ 网关 \(target) 响应正常\n往返延迟: \(String(format: "%.2f ms", ms))\nWi-Fi 物理连接已锁定，心跳保持畅通。"
                : "⚠️ 网关探测失败，已触发自愈看门狗重试连接。"
            Task { @MainActor in
                self.refresh()
                completion(msg)
            }
        }
    }
}

public struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var onQuit: () -> Void
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(viewModel.isActive ? .cyan : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KeepLid 保活卫士")
                            .font(.system(size: 15, weight: .bold))
                        Text(viewModel.isActive ? "已锁定合盖与 Wi-Fi 连接" : "系统处于普通睡眠模式")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isActive ? "保活中" : "空闲")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(viewModel.isActive ? .green : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(viewModel.isActive ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
                .cornerRadius(12)
            }
            .padding(.bottom, 2)
            
            // Master Action Button
            Button(action: {
                viewModel.toggleKeepAwake()
            }) {
                HStack {
                    Image(systemName: viewModel.isActive ? "stop.fill" : "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(viewModel.isActive ? "停止保活 (恢复睡眠)" : "开启合盖保活")
                        .font(.system(size: 14, weight: .bold))
                    if viewModel.isActive {
                        Spacer()
                        Text(viewModel.timeRemainingStr)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(viewModel.isActive ? Color.red.opacity(0.85) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Duration Presets (if not active or can switch)
            if !viewModel.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("预设保活时长")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        presetButton(title: "30分钟", seconds: 1800)
                        presetButton(title: "1小时", seconds: 3600)
                        presetButton(title: "2小时", seconds: 7200)
                        presetButton(title: "4小时", seconds: 14400)
                        presetButton(title: "无限期", seconds: 0)
                    }
                }
            }
            
            Divider()
            
            // Status Grid
            VStack(spacing: 8) {
                // Wi-Fi Row
                metricRow(
                    icon: "wifi",
                    title: "Wi-Fi 状态",
                    value: viewModel.wifiConnected
                        ? "已连接 (\(String(format: "%.1f ms", viewModel.wifiLatencyMs)))"
                        : (viewModel.isActive ? "心跳握手中..." : "待命"),
                    badgeColor: viewModel.wifiConnected ? .green : .secondary,
                    subtitle: "网关: \(viewModel.gatewayIP)"
                )
                
                // Clamshell Row
                metricRow(
                    icon: "laptopcomputer",
                    title: "盒盖检测",
                    value: viewModel.isLidClosed ? "盖子已合上 (正常运行中)" : "盖子打开",
                    badgeColor: viewModel.isLidClosed ? .cyan : .secondary,
                    subtitle: "合盖防休眠: \(viewModel.isActive ? "已锁定" : "未开启")"
                )
                
                // Battery Row
                metricRow(
                    icon: viewModel.isCharging ? "bolt.batteryblock.fill" : "battery.100",
                    title: "电池电量",
                    value: "\(viewModel.batteryPercent)% (\(viewModel.isCharging ? "充电中" : "电池供电"))",
                    badgeColor: viewModel.batteryPercent > 20 ? .green : .orange,
                    subtitle: "安全底线: 15% (低电自动休眠)"
                )
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            
            // Feature Flags
            VStack(alignment: .leading, spacing: 6) {
                Text("安全与增强策略")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                featureItem(
                    title: "Wi-Fi 3秒心跳保活",
                    desc: "持续握手路由器，重置 AP 闲置断开计时器",
                    enabled: true
                )
                featureItem(
                    title: "AWDL 智能防丢包",
                    desc: "合盖期间暂停 AirDrop 跳频，网络无抖动",
                    enabled: viewModel.enableAWDLBoost
                )
                featureItem(
                    title: "合盖即时自动锁屏",
                    desc: "无外接屏合盖时调用安全锁屏，保护隐私",
                    enabled: viewModel.enableScreenLock
                )
            }
            
            Divider()
            
            // Footer Actions
            HStack {
                Button("诊断 Wi-Fi 连通性") {
                    viewModel.runWiFiDiagnostics { @MainActor msg in
                        alertMessage = msg
                        showingAlert = true
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                
                Spacer()
                
                Button("退出 KeepLid") {
                    onQuit()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Wi-Fi 诊断结果"),
                message: Text(alertMessage),
                dismissButton: .default(Text("好的"))
            )
        }
    }
    
    private func presetButton(title: String, seconds: Int) -> some View {
        let isSelected = viewModel.selectedDuration == seconds
        return Button(action: {
            viewModel.selectedDuration = seconds
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func metricRow(icon: String, title: String, value: String, badgeColor: Color, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(badgeColor)
                .frame(width: 20)
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(badgeColor)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func featureItem(title: String, desc: String, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(enabled ? .green : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
