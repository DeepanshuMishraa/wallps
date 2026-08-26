import AppKit
import Foundation

final class WallpaperSwitcher {
    static let shared = WallpaperSwitcher()

    let canvas = DesktopCanvas()

    var savedDesktopURL: URL? { desktopSource?.url }
    var savedDesktopSource: DesktopSource? { desktopSource }
    var savedLoginURL: URL? { loginSource?.url }
    var savedLoginSource: LoginSource? { loginSource }
    var loginImageURL: URL? { loginSource?.url }

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
    private var loginSource: LoginSource?
    private var expectedSystemURLs: [UInt32: URL] = [:]
    private var pendingAdoptionURL: URL?
    private var pendingAdoptionSince: Date?
    private var reconcileTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var didReapplyAtLaunch = false
    private let launchDate = Date()

    var hasReappliedAtLaunch: Bool { didReapplyAtLaunch }

    private init() {
        if let path = defaults.string(forKey: "WallpsDesktopImagePath") {
            let kind = defaults.string(forKey: "WallpsDesktopSourceKind") ?? "image"
            desktopSource = DesktopSource.from(kindString: kind, path: path)
        }
        if let path = defaults.string(forKey: "WallpsLoginImagePath") {
            let kind = defaults.string(forKey: "WallpsLoginSourceKind") ?? "image"
            loginSource = LoginSource.from(kindString: kind, path: path)
        }
        isPaused = defaults.bool(forKey: "WallpsPaused")
        applyState()
    }

    func arm(desktop: URL, login: LoginSource) {
        arm(desktop: .infer(for: desktop), login: login)
    }

    func arm(desktop: DesktopSource, login: LoginSource) {
        desktopSource = desktop
        loginSource = login
        defaults.set(desktop.url.path, forKey: "WallpsDesktopImagePath")
        defaults.set(desktop.kindString, forKey: "WallpsDesktopSourceKind")
        defaults.set(login.url.path, forKey: "WallpsLoginImagePath")
        defaults.set(login.kindString, forKey: "WallpsLoginSourceKind")
        applyState()
        postStateChanged()
    }

    func applyState() {
        guard !isPaused else { return }
        guard hasValidChoices, let login = loginSource, let desktop = desktopSource else { return }
        switch login {
        case .image(let url):
            setSystemWallpaperTracked(url)
        case .video:
            break
        }
        canvas.show(source: desktop)
        startReconciliation()
    }

    /// Applies a new pair chosen in-app (browser or cards) and arms it.
    @MainActor
    func applyAndArm(desktop: DesktopSource?, login: LoginSource?, legacyInstall: Bool = true) async throws -> String {
        guard !isPaused else { throw WallpaperSwitcherError.paused }
        let effectiveLogin = try login ?? requireLogin()
        let effectiveDesktop = try desktop ?? requireDesktop()
        let message: String
        let armedLogin: LoginSource
        switch effectiveLogin {
        case .image(let url):
            message = try await WallpaperService.apply(login: url, legacyInstall: legacyInstall)
            armedLogin = effectiveLogin
        case .video(let url):
            let activated = try await LiveWallpaperManager.shared.setLiveLockScreen(videoURL: url)
            message = "Live lock screen set (\(activated.lastPathComponent))"
            armedLogin = .video(activated)
        }
        arm(desktop: effectiveDesktop, login: armedLogin)
        return message
    }

    /// Applies the saved pair at launch even when the main window stays
    /// hidden (auto-start at login). Runs once per process; the UI side
    /// (ContentView) checks `hasReappliedAtLaunch` to avoid a duplicate pass.
    func reapplyAtLaunchIfNeeded() {
        guard !didReapplyAtLaunch else { return }
        didReapplyAtLaunch = true
        guard !isPaused else { return }
        guard hasValidChoices, let login = loginSource else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task {
                switch login {
                case .image(let url):
                    _ = try? await WallpaperService.apply(login: url, legacyInstall: false)
                case .video(let url):
                    try? await LiveWallpaperManager.shared.reactivateAerial(for: url)
                }
                self.applyState()
            }
            // The OS re-applies its own wallpaper shortly after login; hold
            // the static lock image again a couple of times so it sticks.
            guard case .image = self.loginSource else { return }
            for delay in [2.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          !self.isPaused,
                          self.hasValidChoices,
                          case .image(let login) = self.loginSource else { return }
                    self.setSystemWallpaperTracked(login)
                }
            }
        }
    }

    func restoreDesktopImage() {
        stopReconciliation()
        canvas.tearDown()
        // A live lock screen is the system wallpaper itself — restoring the
        // static desktop image here would kill the animation on the lock.
        if case .video? = loginSource { return }
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
        guard hasValidChoices else { return }
        canvas.reconcile()

        guard case .image(let loginURL)? = loginSource else { return }
        reconcileStaticLock(loginURL)
    }

    private func reconcileStaticLock(_ login: URL) {
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
            // Right after launch (login) the OS re-applies its own wallpaper.
            // Any difference inside this window is system settling, not a
            // deliberate user change in System Settings — do not adopt it.
            guard Date().timeIntervalSince(launchDate) > 15 else { return }
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
    private func requireLogin() throws -> LoginSource {
        if let login = loginSource, FileManager.default.fileExists(atPath: login.url.path) {
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
