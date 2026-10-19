import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var model: BridgeModel!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let project = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        model = BridgeModel(root: project)
        installMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Music Bridge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentMinSize = NSSize(width: 1060, height: 720)
        let host = NSHostingView(rootView: BridgeView(model: model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 24
        host.layer?.masksToBounds = true
        window.contentView = host
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Music Bridge")
        let settings = NSMenuItem(title: "下载设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        let logs = NSMenuItem(title: "运行日志…", action: #selector(openLogs), keyEquivalent: "l")
        logs.target = self; appMenu.addItem(logs)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Music Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        main.addItem(edit)
        let windowItem = NSMenuItem(); windowItem.submenu = NSMenu(title: "窗口")
        windowItem.submenu?.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu?.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { model.settingsExpanded = true }
    @objc private func openLogs() { model.logsExpanded = true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.importing else {
            model.log("正在导入音乐，请等待导入结束后关闭窗口。")
            NSSound.beep()
            return false
        }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.importing {
            model.log("正在导入音乐，请等待导入结束后退出。")
            NSSound.beep()
            return .terminateCancel
        }
        model.shutdown()
        return .terminateNow
    }
}
