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
            guard let window = NSApp.windows.first(where: Self.isContentWindow) else {
                return
            }
            window.delegate = self.windowDelegate
            self.mainWindow = window
        }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(DockIconManager.isHidden ? .accessory : .regular)
        NSApp.unhide(nil)
        if let window = mainWindow ?? NSApp.windows.first(where: Self.isContentWindow) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Brings a still-visible main window back to the front without activating
    /// the app. Used after wallpaper changes that reorder windows (live lock
    /// activation restarts the wallpaper services). Hidden windows stay hidden.
    func reassertMainWindowIfVisible() {
        guard let window = mainWindow ?? NSApp.windows.first(where: Self.isContentWindow) else { return }
        guard window.isVisible else { return }
        mainWindow = window
        window.orderFrontRegardless()
    }

    func hideMainWindowQuietly() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.attachToMainWindowIfNeeded()
            if let window = self.mainWindow ?? NSApp.windows.first(where: Self.isContentWindow) {
                window.orderOut(nil)
                self.mainWindow = window
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func isContentWindow(_ window: NSWindow) -> Bool {
        !window.isKind(of: NSPanel.self)
            && window.contentView != nil
            && window.identifier?.rawValue != DesktopCanvas.windowIdentifier
    }

    /// Menu bar menu, ordered by how often each thing is needed:
    /// what's set now → quick actions → switches → app.
    /// Holding Option turns "Swap Wallpapers" into "Reapply Wallpapers",
    /// a recovery action most people never need to see.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let switcher = WallpaperSwitcher.shared
        let isPaused = switcher.isPaused
        let isComplete = switcher.savedDesktopURL != nil && switcher.savedLoginURL != nil

        menu.addItem(wallpaperItem("Desktop", url: switcher.savedDesktopURL))
        menu.addItem(wallpaperItem("Lock Screen", url: switcher.savedLoginURL))
        menu.addItem(.separator())

        let swap = actionItem("Swap Wallpapers", #selector(swapWallpapers))
        swap.isEnabled = isComplete && !isPaused
        menu.addItem(swap)

        let reapply = actionItem("Reapply Wallpapers", #selector(refresh))
        reapply.isAlternate = true
        reapply.keyEquivalentModifierMask = .option
        reapply.isEnabled = isComplete && !isPaused
        menu.addItem(reapply)

        menu.addItem(actionItem("Browse Wallpapers…", #selector(browse)))
        menu.addItem(.separator())

        let pause = actionItem("Pause Switching", #selector(togglePause))
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)

        let loginItem = actionItem("Launch at Login", #selector(toggleLoginItem))
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(actionItem("Open Wallps", #selector(openWindow)))
        let quit = NSMenuItem(title: "Quit Wallps", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// "Desktop" / "Lock Screen" row with a thumbnail and the file's name.
    /// Clicking it opens the main window, where it can be changed.
    private func wallpaperItem(_ title: String, url: URL?) -> NSMenuItem {
        let item = actionItem(title, #selector(openWindow))
        let name = url?.deletingPathExtension().lastPathComponent ?? "Not set"
        if #available(macOS 14.4, *) {
            item.subtitle = name
        } else {
            item.title = "\(title): \(name)"
        }
        item.image = Self.thumbnail(for: url)
        return item
    }

    private static let thumbnailSize = NSSize(width: 40, height: 25)

    private static func thumbnail(for url: URL?) -> NSImage? {
        guard let url else { return symbol("photo") }
        let isVideo = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
        guard !isVideo else { return symbol("play.rectangle") }
        guard let source = WallpaperImageStore.cachedImage(for: url) else {
            // Warm the cache so the thumbnail is there next time the menu opens.
            WallpaperImageStore.load(url, maxPixelSize: 160) { _ in }
            return symbol("photo")
        }
        let size = thumbnailSize
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.addClip()
            let scale = max(rect.width / source.size.width, rect.height / source.size.height)
            let drawn = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: NSRect(
                x: rect.midX - drawn.width / 2,
                y: rect.midY - drawn.height / 2,
                width: drawn.width,
                height: drawn.height
            ))
            return true
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func swapWallpapers() {
        NotificationCenter.default.post(name: .swapWallpapers, object: nil)
    }

    @objc private func refresh() {
        NotificationCenter.default.post(name: .refreshWallpaperPreviews, object: nil)
    }

    @objc private func browse() {
        showMainWindow()
        NotificationCenter.default.post(name: .openWallpaperBrowser, object: nil)
    }

    @objc private func togglePause() {
        WallpaperSwitcher.shared.isPaused.toggle()
        NotificationCenter.default.post(name: .wallpsStateChanged, object: nil)
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
    var isTerminating = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isTerminating else { return true }
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