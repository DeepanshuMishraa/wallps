import AppKit

private final class CoverImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }

        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let destination = NSRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }
}

final class DesktopCanvas {
    static let windowIdentifier = "WallpsCanvas"

    private var image: NSImage?
    private var currentURL: URL?
    private var windowsByDisplay: [UInt32: NSWindow] = [:]
    private var screenObserver: NSObjectProtocol?

    func show(imageAt url: URL) {
        currentURL = url
        detachObserver()
        WallpaperImageStore.load(url) { [weak self] image in
            guard let self, let image else { return }
            self.image = image
            self.reconcile()
            self.attachObserver()
        }
    }

    /// Rebuilds coverage so every attached display has exactly one
    /// correctly-sized window, drops windows for detached displays.
    func reconcile() {
        guard image != nil else { return }
        rebuildForCurrentScreens()
        attachObserver()
    }

    func tearDown() {
        detachObserver()
        currentURL = nil
        image = nil
        for (_, window) in windowsByDisplay {
            window.orderOut(nil)
        }
        windowsByDisplay.removeAll()
    }

    private func rebuildForCurrentScreens() {
        guard let image else { return }

        var seen = Set<UInt32>()
        for screen in NSScreen.screens {
            guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = raw.uint32Value
            seen.insert(displayID)

            if let existing = windowsByDisplay[displayID] {
                if existing.frame != screen.frame {
                    existing.setFrame(screen.frame, display: false)
                }
                if let coverView = existing.contentView as? CoverImageView, coverView.image !== image {
                    coverView.image = image
                }
            } else {
                let window = makeWindow(screen: screen, image: image)
                window.orderFrontRegardless()
                windowsByDisplay[displayID] = window
            }
        }

        for (displayID, window) in windowsByDisplay where !seen.contains(displayID) {
            window.orderOut(nil)
            windowsByDisplay.removeValue(forKey: displayID)
        }
    }

    private func makeWindow(screen: NSScreen, image: NSImage) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        let coverView = CoverImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        coverView.image = image
        window.contentView = coverView
        return window
    }

    private func attachObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcile()
        }
    }

    private func detachObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }
}