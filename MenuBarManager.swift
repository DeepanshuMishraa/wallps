import AppKit

final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()

    let windowDelegate = WallpsWindowDelegate()
    private var statusItem: NSStatusItem?
    weak var mainWindow: NSWindow?

    private override init() {}

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarIcon()
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func attachToMainWindowIfNeeded() {
        guard mainWindow == nil else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.contentView != nil }) else {
                return
            }
            window.delegate = self.windowDelegate
            self.mainWindow = window
        }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if let window = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
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
        showMainWindow()
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

    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            func tile(_ r: NSRect) {
                let path = NSBezierPath(roundedRect: r, xRadius: 3.5, yRadius: 3.5)
                path.lineWidth = 1.6
                path.stroke()
            }
            tile(NSRect(x: 1.5, y: 10, width: 10.5, height: 7.5))
            tile(NSRect(x: 7, y: 1.5, width: 10.5, height: 7.5))
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class WallpsWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
        MenuBarManager.shared.mainWindow = sender
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        return false
    }
}