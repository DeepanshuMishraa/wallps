import AppKit
import Foundation

final class WallpaperSwitcher {
    static let shared = WallpaperSwitcher()

    let canvas = DesktopCanvas()

    var savedDesktopURL: URL? { desktopImageURL }
    var savedLoginURL: URL? { loginImageURL }

    private let defaults = UserDefaults.standard
    private var desktopImageURL: URL?
    private var loginImageURL: URL?

    private init() {
        if let path = defaults.string(forKey: "WallpsDesktopImagePath") {
            desktopImageURL = URL(fileURLWithPath: path)
        }
        if let path = defaults.string(forKey: "WallpsLoginImagePath") {
            loginImageURL = URL(fileURLWithPath: path)
        }
        applyState()
    }

    func arm(desktop: URL, login: URL) {
        desktopImageURL = desktop
        loginImageURL = login
        defaults.set(desktop.path, forKey: "WallpsDesktopImagePath")
        defaults.set(login.path, forKey: "WallpsLoginImagePath")
        applyState()
    }

    func applyState() {
        if let loginImageURL, FileManager.default.fileExists(atPath: loginImageURL.path) {
            setSystemWallpaper(loginImageURL)
        }
        if let desktopImageURL, FileManager.default.fileExists(atPath: desktopImageURL.path) {
            canvas.show(imageAt: desktopImageURL)
        }
    }

    func restoreDesktopImage() {
        canvas.tearDown()
        if let desktopImageURL, FileManager.default.fileExists(atPath: desktopImageURL.path) {
            setSystemWallpaper(desktopImageURL)
        }
    }

    private func setSystemWallpaper(_ url: URL) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }
}