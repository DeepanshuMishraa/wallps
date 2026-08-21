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
    private var reconcileTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

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
        guard hasValidChoices, let login = loginImageURL else { return }
        setSystemWallpaper(login)
        canvas.show(imageAt: desktopImageURL!)
        startReconciliation()
    }

    func restoreDesktopImage() {
        stopReconciliation()
        canvas.tearDown()
        if let desktopImageURL, FileManager.default.fileExists(atPath: desktopImageURL.path) {
            setSystemWallpaper(desktopImageURL)
        }
    }

    /// Self-healing pass: makes sure every attached display is covered by the
    /// canvas and still carries the lock image as its system wallpaper.
    func reconcile() {
        guard hasValidChoices else { return }
        canvas.reconcile()

        let login = loginImageURL!
        for screen in NSScreen.screens where NSWorkspace.shared.desktopImageURL(for: screen) != login {
            setSystemWallpaper(login)
            return
        }
    }

    private var hasValidChoices: Bool {
        guard let desktop = desktopImageURL, let login = loginImageURL else { return false }
        return FileManager.default.fileExists(atPath: desktop.path)
            && FileManager.default.fileExists(atPath: login.path)
    }

    private func setSystemWallpaper(_ url: URL) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    private func startReconciliation() {
        observeWorkspace()
        guard reconcileTimer == nil else { return }
        DispatchQueue.main.async { [weak self] in self?.reconcile() }
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
    }

    private func stopReconciliation() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func observeWorkspace() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.scheduleCatchUpSweeps()
                }
            )
        }
    }

    /// Displays re-enumerate in stages after a wake; sweep several times so
    /// late-arriving screens get covered without user action.
    private func scheduleCatchUpSweeps() {
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reconcile()
            }
        }
    }
}