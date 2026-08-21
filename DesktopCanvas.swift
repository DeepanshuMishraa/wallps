import AppKit

final class DesktopCanvas {
    static let windowIdentifier = "WallpsCanvas"

    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var currentURL: URL?

    func show(imageAt url: URL) {
        currentURL = url
        detachObserver()
        WallpaperImageStore.load(url) { [weak self] image in
            guard let self, let image else { return }
            self.render(image: image)
        }
    }

    func tearDown() {
        detachObserver()
        currentURL = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func render(image: NSImage) {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        for screen in NSScreen.screens {
            let window = makeWindow(screen: screen, image: image)
            window.orderFrontRegardless()
            windows.append(window)
        }
        attachObserver()
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
            guard let self, let url = self.currentURL else { return }
            self.show(imageAt: url)
        }
    }

    private func detachObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }
}