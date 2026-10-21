import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject,NSApplicationDelegate,NSWindowDelegate,NSMenuDelegate {
    let model = HomeModel()
    var window: NSWindow!
    var touch: HomeTouch!
    var status: NSStatusItem!
    var loginItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        touch = HomeTouch(model:model)
        model.onChange = { [weak self] in self?.touch.update() }
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName:"house.fill",accessibilityDescription:"家控台")
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(withTitle:"家控台 · 常驻运行",action:nil,keyEquivalent:"")
        menu.addItem(.separator())
        menu.addItem(withTitle:"展开 Touch Bar 控制台",action:#selector(showBar),keyEquivalent:"")
        menu.addItem(withTitle:"恢复 Touch Bar 入口",action:#selector(repairEntry),keyEquivalent:"")
        menu.addItem(withTitle:"打开主面板",action:#selector(showWindow),keyEquivalent:"")
        menu.addItem(withTitle:"刷新设备状态",action:#selector(refresh),keyEquivalent:"")
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle:"登录时启动",action:#selector(toggleLogin),keyEquivalent:"")
        menu.addItem(.separator())
        menu.addItem(withTitle:"退出家控台",action:#selector(quit),keyEquivalent:"q")
        for item in menu.items { item.target = self }
        status.menu = menu
        let root = ShareRoot(model:model,showBar:{ [weak self] in self?.showBar() })
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "家控台 · 独立分享版"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named:.darkAqua)
        window.backgroundColor = NSColor(red:0.035,green:0.047,blue:0.078,alpha:1)
        window.contentView = NSHostingView(rootView:root)
        window.minSize = NSSize(width:1060,height:770)
        window.delegate = self; window.isReleasedWhenClosed = false
        window.touchBar = touch.bar
        let notifications=NSWorkspace.shared.notificationCenter
        notifications.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
        notifications.addObserver(self,selector:#selector(didWake),name:NSWorkspace.screensDidWakeNotification,object:nil)
        notifications.addObserver(self,selector:#selector(didWake),name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
        notifications.addObserver(self,selector:#selector(controlStripLaunched(_:)),name:NSWorkspace.didLaunchApplicationNotification,object:nil)
        window.center(); showWindow(); model.start()
    }
    func menuWillOpen(_ menu: NSMenu) { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    @objc func showWindow() { model.windowVisible=true; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); model.requestStates() }
    func windowWillClose(_ notification: Notification) { model.windowVisible=false }
    func windowDidMiniaturize(_ notification: Notification) { model.windowVisible=false }
    func windowDidDeminiaturize(_ notification: Notification) { model.windowVisible=true; model.requestStates() }
    func windowDidBecomeKey(_ notification: Notification) { model.windowVisible=true; model.requestStates() }
    func applicationDidBecomeActive(_ notification: Notification) { model.requestStates() }
    @objc func showBar() { if model.globalAvailable { touch.show() } else { showWindow(); model.failed = true; model.message = "当前系统未提供全局 Touch Bar 接口，仍可从主面板控制。" } }
    @objc func didWake() { touch.scheduleEntryRecovery(reason:"wake-or-unlock"); model.requestStates() }
    @objc func controlStripLaunched(_ notification: Notification) {
        if let app=notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.apple.controlstrip" { touch.scheduleEntryRecovery(reason:"control-strip-launched") }
    }
    @objc func repairEntry() { touch.recoverEntry(); touch.show() }
    @objc func refresh() { model.refresh() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { model.message = "登录启动需要在系统设置中批准。"; SMAppService.openSystemSettingsLoginItems() }
        } catch { model.failed = true; model.message = "未能更改登录启动，请先将 App 保留在固定位置后重试。"; showWindow() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { touch.shutdown() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
