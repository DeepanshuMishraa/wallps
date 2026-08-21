import AppKit

final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()

    let windowDelegate = WallpsWindowDelegate()
    private var statusItem: NSStatusItem?
    private var mainMenu: NSMenu?
    weak var mainWindow: NSWindow?

    private override init() {}

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.2.swap",
                accessibilityDescription: "Wallps"
            )
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        mainMenu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let desktop = WallpaperSwitcher.shared.savedDesktopURL?.lastPathComponent ?? "Not set"
        let login = WallpaperSwitcher.shared.savedLoginURL?.lastPathComponent ?? "Not set"

        menu.addItem(disabledItem("Wallps"))
        menu.addItem(disabledItem("Desktop: \(desktop)"))
        menu.addItem(disabledItem("Lock screen: \(login)"))
        menu.addItem(.separator())
        menu.addItem(actionItem("Set wallpapers", #selector(setWallpapers)))
        menu.addItem(actionItem("Refresh", #selector(refresh)))
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(actionItem("Open Wallps", #selector(openWindow)))
        menu.addItem(actionItem("Quit", #selector(quit)))
    }

    @objc private func setWallpapers() {
        NotificationCenter.default.post(name: .setWallpapers, object: nil)
    }

    @objc private func refresh() {
        NotificationCenter.default.post(name: .refreshWallpaperPreviews, object: nil)
    }

    @objc private func toggleLoginItem() {
        if LoginItemManager.isEnabled {
            try? LoginItemManager.disable()
        } else {
            try? LoginItemManager.enable()
        }
    }

    @objc private func openWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

final class WallpsWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        MenuBarManager.shared.mainWindow = sender
        return false
    }
}