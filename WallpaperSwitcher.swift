import AppKit
import Foundation

final class WallpaperSwitcher {
    static let shared = WallpaperSwitcher()

    let canvas = DesktopCanvas()

    var savedDesktopURL: URL? { desktopSource?.url }
    var savedDesktopSource: DesktopSource? { desktopSource }
    var savedLoginURL: URL? { loginImageURL }

    var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: "WallpsPaused")
            if isPaused {
                stopReconciliation()
                canvas.tearDown()
            } else {
                applyState()
            }
        }
    }

    private let defaults = UserDefaults.standard
    private var desktopSource: DesktopSource?
    private var loginImageURL: URL?
    private var expectedSystemURLs: [UInt32: URL] = [:]
    private var pendingAdoptionURL: URL?
    private var pendingAdoptionSince: Date?
    private var reconcileTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        if let path = defaults.string(forKey: "WallpsDesktopImagePath") {
            let kind = defaults.string(forKey: "WallpsDesktopSourceKind") ?? "image"
            desktopSource = DesktopSource.from(kindString: kind, path: path)
        }
        if let path = defaults.string(forKey: "WallpsLoginImagePath") {
            loginImageURL = URL(fileURLWithPath: path)
        }
        isPaused = defaults.bool(forKey: "WallpsPaused")
        applyState()
    }

    func arm(desktop: URL, login: URL) {
        arm(desktop: .infer(for: desktop), login: login)
    }

    func arm(desktop: DesktopSource, login: URL) {
        desktopSource = desktop
        loginImageURL = login
        defaults.set(desktop.url.path, forKey: "WallpsDesktopImagePath")
        defaults.set(desktop.kindString, forKey: "WallpsDesktopSourceKind")
        defaults.set(login.path, forKey: "WallpsLoginImagePath")
        applyState()
        postStateChanged()
    }

    func applyState() {
        guard !isPaused else { return }
        guard hasValidChoices, let login = loginImageURL, let desktop = desktopSource else { return }
        setSystemWallpaperTracked(login)
        canvas.show(source: desktop)
        startReconciliation()
    }

    /// Applies a new pair chosen in-app (browser or cards) and arms it.
    @MainActor
    func applyAndArm(desktop: DesktopSource?, login: URL?, legacyInstall: Bool = true) async throws -> String {
        guard !isPaused else { throw WallpaperSwitcherError.paused }
        let effectiveLogin = try login ?? requireLogin()
        let effectiveDesktop = try desktop ?? requireDesktop()
        let message = try await WallpaperService.apply(login: effectiveLogin, legacyInstall: legacyInstall)
        arm(desktop: effectiveDesktop, login: effectiveLogin)
        return message
    }

    func restoreDesktopImage() {
        stopReconciliation()
        canvas.tearDown()
        switch desktopSource {
        case .image(let url):
            if FileManager.default.fileExists(atPath: url.path) {
                setSystemWallpaper(url)
            }
        case .video(let url):
            if let cached = cachedPoster(for: url), FileManager.default.fileExists(atPath: cached.path) {
                setSystemWallpaper(cached)
            }
        case nil:
            break
        }
    }

    /// Self-healing pass: keeps every attached display covered by the canvas,
    /// holds the lock image as system wallpaper, and adopts external changes
    /// made from System Settings instead of reverting them.
    func reconcile() {
        guard !isPaused else { return }
        guard hasValidChoices, let login = loginImageURL else { return }
        canvas.reconcile()

        var externalCandidate: URL?
        for screen in NSScreen.screens {
            guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = raw.uint32Value
            let current = NSWorkspace.shared.desktopImageURL(for: screen)

            if current == nil {
                if expectedSystemURLs[displayID] != nil {
                    setSystemWallpaperTracked(login, screens: [screen])
                }
                continue
            }

            if current == expectedSystemURLs[displayID] || current == login {
                expectedSystemURLs[displayID] = login
                clearPendingAdoptionIfMatching(current)
                continue
            }

            if externalCandidate == nil {
                externalCandidate = current
            }
        }

        if let candidate = externalCandidate {
            if candidate != pendingAdoptionURL {
                pendingAdoptionURL = candidate
                pendingAdoptionSince = Date()
            } else if let since = pendingAdoptionSince,
                      Date().timeIntervalSince(since) >= 2.0 {
                clearPendingAdoption()
                adoptExternalChange(url: candidate, login: login)
            }
        } else if pendingAdoptionURL != nil {
            clearPendingAdoption()
        }
    }

    private func clearPendingAdoptionIfMatching(_ url: URL?) {
        guard url != nil, url == pendingAdoptionURL else { return }
        clearPendingAdoption()
    }

    private func clearPendingAdoption() {
        pendingAdoptionURL = nil
        pendingAdoptionSince = nil
    }

    /// A wallpaper picked in System Settings becomes the visible desktop
    /// content; the lock-screen image stays armed underneath as system
    /// wallpaper so the lock screen keeps working.
    private func adoptExternalChange(url: URL, login: URL) {
        let source = DesktopSource.infer(for: url)
        switch source {
        case .image(let imageURL):
            guard FileManager.default.isReadableFile(atPath: imageURL.path),
                  NSImageRep(contentsOf: imageURL) != nil else {
                return
            }
        case .video(let videoURL):
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                return
            }
        }

        desktopSource = source
        persistDesktopSource()
        canvas.show(source: source)
        setSystemWallpaperTracked(login)
        postStateChanged()
    }

    private func persistDesktopSource() {
        guard let desktopSource else { return }
        defaults.set(desktopSource.url.path, forKey: "WallpsDesktopImagePath")
        defaults.set(desktopSource.kindString, forKey: "WallpsDesktopSourceKind")
    }

    private var hasValidChoices: Bool {
        guard let desktop = desktopSource, let login = loginImageURL else { return false }
        return FileManager.default.fileExists(atPath: desktop.url.path)
            && FileManager.default.fileExists(atPath: login.path)
    }

    @MainActor
    private func requireLogin() throws -> URL {
        if let login = loginImageURL, FileManager.default.fileExists(atPath: login.path) {
            return login
        }
        throw WallpaperSwitcherError.missingLockImage
    }

    @MainActor
    private func requireDesktop() throws -> DesktopSource {
        if let desktop = desktopSource, FileManager.default.fileExists(atPath: desktop.url.path) {
            return desktop
        }
        throw WallpaperSwitcherError.missingDesktopImage
    }

    private func cachedPoster(for videoURL: URL) -> URL? {
        let id = (videoURL.deletingPathExtension().lastPathComponent)
        return SystemWallpaperCatalog.postersDirectory
            .appendingPathComponent("\(SystemWallpaperCatalog.sanitized(id))-poster.png")
    }

    private func setSystemWallpaper(_ url: URL) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    private func setSystemWallpaperTracked(_ url: URL, screens: [NSScreen]? = nil) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        for screen in screens ?? NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            if let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                expectedSystemURLs[raw.uint32Value] = url
            }
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
        clearPendingAdoption()
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

    private func postStateChanged() {
        NotificationCenter.default.post(name: .wallpsStateChanged, object: nil)
    }
}

enum WallpaperSwitcherError: LocalizedError {
    case paused
    case missingLockImage
    case missingDesktopImage

    var errorDescription: String? {
        switch self {
        case .paused:
            return "Wallps is paused. Turn protection back on to manage wallpapers."
        case .missingLockImage:
            return "Choose a lock-screen image first, then try again."
        case .missingDesktopImage:
            return "Choose a desktop wallpaper first, then try again."
        }
    }
}
