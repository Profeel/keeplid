import AppKit
import SwiftUI
import KeepLidCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private let engine = KeepLidEngine.shared
    private let viewModel = DashboardViewModel()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Runs quietly in menu bar, no dock icon
        
        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.behavior = .transient
        
        let contentView = DashboardView(viewModel: viewModel, onQuit: { [weak self] in
            self?.quitApp()
        })
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateStatusItem()
        
        // 1-second UI updater
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        if engine.isRunning {
            engine.stop(reason: "App Quit")
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right-click: show quick menu
            showContextMenu()
        } else {
            // Left-click: toggle popover
            if popover.isShown {
                popover.performClose(sender)
            } else {
                viewModel.refresh()
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        
        let state = KeepLidState.load()
        let isRunning = engine.isRunning || state.isActive
        
        if isRunning {
            if let exp = state.expiresAt {
                let remain = max(0, Int(exp.timeIntervalSinceNow))
                let m = remain / 60
                let s = remain % 60
                button.title = "🛡️ \(String(format: "%02d:%02d", m, s))"
            } else {
                button.title = "🛡️ ⚡"
            }
        } else {
            button.title = "🛡️ 💤"
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        let state = KeepLidState.load()
        let isRunning = engine.isRunning || state.isActive
        
        let header = NSMenuItem(title: isRunning ? "KeepLid: 保活中 ⚡" : "KeepLid: 未运行 💤", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())
        
        if isRunning {
            let stop = NSMenuItem(title: "停止保活 (恢复休眠)", action: #selector(contextStop), keyEquivalent: "s")
            stop.target = self
            menu.addItem(stop)
        } else {
            let start = NSMenuItem(title: "开启保活 (无限期)", action: #selector(contextStart), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        }
        
        menu.addItem(NSMenuItem.separator())
        let openControl = NSMenuItem(title: "打开控制面板...", action: #selector(openControlPanel), keyEquivalent: "")
        openControl.target = self
        menu.addItem(openControl)
        
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "退出 KeepLid", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Detach so subsequent left clicks trigger action
    }
    
    @objc private func contextStop() {
        engine.stop(reason: "从右键菜单停止")
        updateStatusItem()
    }
    
    @objc private func contextStart() {
        _ = engine.start(durationSeconds: 0)
        updateStatusItem()
    }
    
    @objc private func openControlPanel() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc private func quitApp() {
        if engine.isRunning {
            engine.stop(reason: "Quit App")
        }
        NSApp.terminate(nil)
    }
}
