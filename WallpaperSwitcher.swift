import AppKit
import Foundation

final class WallpaperSwitcher {
    static let shared = WallpaperSwitcher()

    var savedDesktopURL: URL? { desktopImageURL }
    var savedLoginURL: URL? { loginImageURL }

    private let defaults = UserDefaults.standard
    private var desktopImageURL: URL?
    private var loginImageURL: URL?
    private var showingLoginImage = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        if let path = defaults.string(forKey: "WallpsDesktopImagePath") {
            desktopImageURL = URL(fileURLWithPath: path)
        }
        if let path = defaults.string(forKey: "WallpsLoginImagePath") {
            loginImageURL = URL(fileURLWithPath: path)
        }
        guard desktopImageURL != nil, loginImageURL != nil else { return }
        register()
        restoreDesktopImage()
    }

    func arm(desktop: URL, login: URL) {
        desktopImageURL = desktop
        loginImageURL = login
        defaults.set(desktop.path, forKey: "WallpsDesktopImagePath")
        defaults.set(login.path, forKey: "WallpsLoginImagePath")
        register()
    }

    func restoreDesktopImage() {
        guard let desktopImageURL else { return }
        showingLoginImage = false
        setDesktopImage(desktopImageURL)
    }

    private func register() {
        guard observers.isEmpty else { return }
        for name in [
            "com.apple.screenIsLocked",
            "com.apple.screensaverDidStart",
            "com.apple.sessionDidResignActive",
        ] {
            observe(name) { switcher in
                switcher.showLoginImage()
            }
        }
        for name in [
            "com.apple.screenIsUnlocked",
            "com.apple.screensaverDidStop",
            "com.apple.sessionDidBecomeActive",
        ] {
            observe(name) { switcher in
                switcher.showDesktopImage()
            }
        }
    }

    private func observe(_ name: String, action: @escaping (WallpaperSwitcher) -> Void) {
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                action(self)
            }
        )
    }

    private func showLoginImage() {
        guard !showingLoginImage, let loginImageURL else { return }
        showingLoginImage = true
        setDesktopImage(loginImageURL)
    }

    private func showDesktopImage() {
        guard showingLoginImage, let desktopImageURL else { return }
        showingLoginImage = false
        setDesktopImage(desktopImageURL)
    }

    private func setDesktopImage(_ url: URL) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }
}