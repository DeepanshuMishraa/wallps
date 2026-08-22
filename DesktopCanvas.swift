import AVFoundation
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

private final class PlayerCoverView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVQueuePlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

final class DesktopCanvas {
    static let windowIdentifier = "WallpsCanvas"

    private var content: DesktopSource?
    private var image: NSImage?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var windowsByDisplay: [UInt32: NSWindow] = [:]
    private var screenObserver: NSObjectProtocol?

    func show(source: DesktopSource) {
        detachObserver()
        stopPlayback()
        removeAllWindows()

        switch source {
        case .image(let url):
            WallpaperImageStore.load(url) { [weak self] loadedImage in
                guard let self, let loadedImage else { return }
                self.content = source
                self.image = loadedImage
                self.reconcile()
                self.attachObserver()
            }
        case .video(let url):
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            content = source
            image = nil
            queuePlayer.play()
            reconcile()
            attachObserver()
        }
    }

    /// Rebuilds coverage so every attached display has exactly one
    /// correctly-sized window, drops windows for detached displays.
    func reconcile() {
        guard content != nil else { return }
        rebuildForCurrentScreens()
        attachObserver()
    }

    func tearDown() {
        detachObserver()
        content = nil
        image = nil
        stopPlayback()
        for (_, window) in windowsByDisplay {
            window.orderOut(nil)
        }
        windowsByDisplay.removeAll()
    }

    private func stopPlayback() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player = nil
    }

    private func removeAllWindows() {
        for (_, window) in windowsByDisplay {
            window.orderOut(nil)
        }
        windowsByDisplay.removeAll()
    }

    private func rebuildForCurrentScreens() {
        guard content != nil else { return }

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
            } else {
                let window = makeWindow(screen: screen)
                window.orderFrontRegardless()
                windowsByDisplay[displayID] = window
            }
        }

        for (displayID, window) in windowsByDisplay where !seen.contains(displayID) {
            window.orderOut(nil)
            windowsByDisplay.removeValue(forKey: displayID)
        }
    }

    private func makeWindow(screen: NSScreen) -> NSWindow {
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

        if let player {
            window.contentView = PlayerCoverView(player: player)
        } else {
            let coverView = CoverImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            coverView.image = image
            window.contentView = coverView
        }
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
