import AppKit

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
                if let imageView = existing.contentView as? NSImageView, imageView.image !== image {
                    imageView.image = image
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
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = imageView
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