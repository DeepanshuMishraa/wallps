import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

enum ImportTarget {
    case desktop
    case login

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .login: return "Lock Screen"
        }
    }

    var subtitle: String {
        switch self {
        case .desktop: return "Active workspace background"
        case .login: return "Lock screen wallpaper"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "macbook"
        case .login: return "lock.display"
        }
    }
}

struct ContentView: View {
    @State private var desktopImage: URL?
    @State private var loginImage: URL?
    @State private var isImporting = false
    @State private var pendingTarget: ImportTarget = .desktop
    @State private var isApplying = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var alert: WallpaperService.AlertMessage?
    @State private var launchAtLogin = false
    @State private var showingLoginPrompt = false
    @State private var didAutoReapply = false
    @State private var isPaused = false
    @State private var showingBrowser = false

    var body: some View {
        HStack(spacing: 0) {
            // Left Control Column (38%)
            leftControlPanel
                .frame(width: 250)
                .background(Design.surface)
                .overlay(
                    GeometryReader { geo in
                        HStack {
                            Spacer()
                            Rectangle()
                                .fill(Design.hairline)
                                .frame(width: 1)
                        }
                    }
                )

            // Right Visual Stage (62%)
            rightVisualStage
                .frame(maxWidth: .infinity)
        }
        .background(Design.background)
        .frame(minWidth: 680, idealWidth: 780, minHeight: 520, idealHeight: 580)
        .background(WindowChromeConfigurator())
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                switch pendingTarget {
                case .desktop: desktopImage = url
                case .login: loginImage = url
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setWallpapers)) { _ in
            applyWallpapers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewLockScreen)) { _ in
            triggerLockScreenPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWallpaperPreviews)) { _ in
            didAutoReapply = false
            autoReapplySavedChoices(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            MenuBarManager.shared.showMainWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wallpsStateChanged)) { _ in
            syncCardsFromSwitcher()
            isPaused = WallpaperSwitcher.shared.isPaused
        }
        .sheet(isPresented: $showingBrowser) {
            SystemWallpaperBrowserView()
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Allow Wallps to launch at login?",
            isPresented: $showingLoginPrompt,
            titleVisibility: .visible
        ) {
            Button("Allow") {
                Task {
                    do {
                        try LoginItemManager.enable()
                    } catch {
                        launchAtLogin = false
                        alert = WallpaperService.AlertMessage(
                            title: "Auto-start unavailable",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            Button("Not now", role: .cancel) {
                launchAtLogin = false
            }
        } message: {
            Text("Wallps starts silently at login and automatically keeps desktop and lock screen wallpapers synchronized.")
        }
        .onAppear {
            FontRegistrar.registerBundledFonts()
            MenuBarManager.shared.attachToMainWindowIfNeeded()
            isPaused = WallpaperSwitcher.shared.isPaused
            autoReapplySavedChoices()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
    }

    // MARK: - Left Control Panel

    private var leftControlPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Title & Version Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Wallps")
                        .font(Design.font(16, weight: .bold))
                        .foregroundStyle(Design.ink)

                    Text("v\(appVersion)")
                        .font(Design.font(9, weight: .semibold))
                        .foregroundStyle(Design.inkTertiary)
                }

                HStack(spacing: 6) {
                    StatusDot(
                        filled: true,
                        isGlowing: !isPaused,
                        customColor: isPaused ? Design.inkTertiary : (statusIsError ? Design.error : Design.success)
                    )
                    Text(isPaused ? "Engine Paused" : "Engine Active")
                        .font(Design.font(9.5, weight: .bold))
                        .foregroundStyle(isPaused ? Design.inkTertiary : Design.success)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)

            // Settings & Preferences Rows
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BEHAVIOR")
                        .font(Design.font(9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Design.inkTertiary)

                    // Launch at Login Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch on boot")
                                .font(Design.font(11, weight: .semibold))
                                .foregroundStyle(Design.ink)
                            Text("Auto-start engine")
                                .font(Design.font(9, weight: .regular))
                                .foregroundStyle(Design.inkTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(PillToggleStyle())
                    }
                    .onAppear { launchAtLogin = LoginItemManager.isEnabled }
                    .onChange(of: launchAtLogin) { enabled in
                        guard enabled else {
                            Task { try? LoginItemManager.disable() }
                            return
                        }
                        guard !LoginItemManager.isEnabled else { return }
                        showingLoginPrompt = true
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SERVICE STATE")
                        .font(Design.font(9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Design.inkTertiary)

                    // Pause Switching Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause switching")
                                .font(Design.font(11, weight: .semibold))
                                .foregroundStyle(Design.ink)
                            Text("Adopt system choices")
                                .font(Design.font(9, weight: .regular))
                                .foregroundStyle(Design.inkTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $isPaused)
                            .labelsHidden()
                            .toggleStyle(PillToggleStyle())
                    }
                    .onChange(of: isPaused) { paused in
                        WallpaperSwitcher.shared.isPaused = paused
                        if !paused {
                            syncCardsFromSwitcher()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Footer Actions
            VStack(spacing: 8) {
                GhostIconButton(
                    symbol: "sparkles.rectangle.stack",
                    text: "Explore Catalog",
                    help: "Browse Apple system wallpapers & dynamic live aerials"
                ) {
                    showingBrowser = true
                }
                .frame(maxWidth: .infinity)

                PrimaryActionButton(
                    title: isApplying ? "Applying…" : "Apply Pair (⌘↵)",
                    isLoading: isApplying,
                    keyEquivalent: .return
                ) {
                    applyWallpapers()
                }
                .frame(maxWidth: .infinity)
                .disabled(desktopImage == nil || loginImage == nil || isApplying || isPaused)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Right Visual Stage (Asymmetrical Showcase Stage)

    private var rightVisualStage: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header Info Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallpapers")
                        .font(Design.font(13.5, weight: .bold))
                        .foregroundStyle(Design.ink)
                    Text(statusText)
                        .font(Design.font(10.5, weight: .regular))
                        .foregroundStyle(statusIsError ? Design.error : Design.inkSecondary)
                }

                Spacer()

                if loginImage != nil {
                    Button {
                        triggerLockScreenPreview()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Preview (⌘⇧P)")
                                .font(Design.font(10, weight: .bold))
                                .tracking(0.6)
                        }
                        .foregroundStyle(Design.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(Design.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Design.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            // Staggered Asymmetric Viewport Stack
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Staggered Desktop (Shifted left/right dynamically)
                    HStack {
                        wallpaperViewport(target: .desktop, image: desktopImage)
                            .frame(maxWidth: 360)
                        Spacer()
                    }

                    // Staggered Lock Screen
                    HStack {
                        Spacer()
                        wallpaperViewport(target: .login, image: loginImage)
                            .frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    private func wallpaperViewport(target: ImportTarget, image: URL?) -> some View {
        WallpaperViewportView(
            target: target,
            url: image,
            onPick: { chooseImage(for: target) },
            onPreview: {
                if target == .login {
                    triggerLockScreenPreview()
                }
            },
            onAcceptImage: { url in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    switch target {
                    case .desktop: desktopImage = url
                    case .login: loginImage = url
                    }
                }
            },
            onClear: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    switch target {
                    case .desktop: desktopImage = nil
                    case .login: loginImage = nil
                    }
                }
            }
        )
    }

    private var statusText: String {
        if let message = statusMessage {
            return message
        }
        if isPaused {
            return "Paused · System Settings in control"
        }
        return "Armed · Press ⌘⇧P to preview lock screen"
    }

    private func chooseImage(for target: ImportTarget) {
        pendingTarget = target
        isImporting = true
    }

    private func triggerLockScreenPreview() {
        guard let url = loginImage ?? desktopImage else { return }
        LockScreenPreviewManager.shared.show(url: url)
    }

    private func applyWallpapers() {
        guard let desktopImage, let loginImage else { return }
        Task {
            isApplying = true
            statusMessage = "Applying wallpapers…"
            statusIsError = false
            do {
                statusMessage = try await WallpaperService.apply(login: loginImage)
                WallpaperSwitcher.shared.arm(desktop: desktopImage, login: loginImage)
            } catch {
                statusMessage = "Could not apply wallpapers."
                statusIsError = true
                alert = WallpaperService.AlertMessage(title: "Wallpaper setup failed", message: error.localizedDescription)
            }
            isApplying = false
        }
    }

    private func syncCardsFromSwitcher() {
        let switcher = WallpaperSwitcher.shared
        if let desktopURL = switcher.savedDesktopURL,
           FileManager.default.fileExists(atPath: desktopURL.path) {
            desktopImage = desktopURL
        }
        if let loginURL = switcher.savedLoginURL,
           FileManager.default.fileExists(atPath: loginURL.path) {
            loginImage = loginURL
        }
    }

    private func autoReapplySavedChoices(force: Bool = false) {
        guard !didAutoReapply || force else { return }
        didAutoReapply = true
        guard !WallpaperSwitcher.shared.isPaused else { return }

        let savedDesktop = WallpaperSwitcher.shared.savedDesktopURL
        let savedLogin = WallpaperSwitcher.shared.savedLoginURL
        let desktopIsValid = savedDesktop.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let loginIsValid = savedLogin.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        if loginIsValid, let savedLogin {
            loginImage = savedLogin
        } else {
            loginImage = WallpaperService.currentLoginImageURL()
        }

        if desktopIsValid, let savedDesktop {
            desktopImage = savedDesktop
        } else {
            desktopImage = NSScreen.screens.first.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                ?? savedDesktop
        }

        guard desktopIsValid, loginIsValid, let savedDesktop, let savedLogin else { return }
        Task {
            isApplying = true
            statusMessage = "Reapplying saved wallpapers…"
            statusIsError = false
            do {
                statusMessage = try await WallpaperService.apply(login: savedLogin, legacyInstall: false)
                WallpaperSwitcher.shared.arm(desktop: savedDesktop, login: savedLogin)
            } catch {
                statusMessage = "Could not reapply saved wallpapers."
                statusIsError = true
            }
            isApplying = false
        }
    }
}

// MARK: - Modern Wallpaper Viewport

private struct WallpaperViewportView: View {
    let target: ImportTarget
    let url: URL?
    let onPick: () -> Void
    let onPreview: () -> Void
    let onAcceptImage: (URL) -> Void
    let onClear: () -> Void

    @State private var cacheGeneration = 0
    @State private var dropping = false
    @State private var hovering = false
    @State private var videoPreview: NSImage?

    private var isVideo: Bool {
        ["mov", "mp4", "m4v"].contains(url?.pathExtension.lowercased() ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Viewport Header Info
            HStack(spacing: 6) {
                Image(systemName: target.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.inkSecondary)

                Text(target.title.uppercased())
                    .font(Design.font(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Design.ink)

                if isVideo {
                    Text("LIVE")
                        .font(Design.font(8.5, weight: .bold))
                        .foregroundStyle(Design.accentInk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Design.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }

                Spacer()

                if let url {
                    Text(url.lastPathComponent)
                        .font(Design.font(9.5, weight: .medium))
                        .foregroundStyle(Design.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }

            // Aspect 16:10 Bezel Display Frame
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Design.surface)

                GeometryReader { geo in
                    imageLayer(size: geo.size)
                }

                if url != nil {
                    // Smooth subtle ambient dimming overlay
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Floating hardware action bar
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: onClear) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text("CLEAR")
                                        .font(Design.font(9, weight: .bold))
                                        .tracking(0.6)
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()

                            Spacer()

                            if target == .login {
                                Button(action: onPreview) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text("PREVIEW")
                                            .font(Design.font(9, weight: .bold))
                                            .tracking(0.6)
                                    }
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4.5)
                                    .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .pointerOnHover()
                            }

                            Button(action: onPick) {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text("CHANGE")
                                        .font(Design.font(9, weight: .bold))
                                        .tracking(0.6)
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()
                        }
                        .padding(8)
                    }
                }
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        dropping ? Design.accent : (hovering ? Design.hairlineStrong : Design.hairline),
                        lineWidth: dropping ? 2 : 1
                    )
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    WallpaperImageStore.load(url) { image in
                        if image != nil {
                            onAcceptImage(url)
                        }
                    }
                }
                return true
            }
            .task(id: url) {
                await reloadPreview()
            }
        }
    }

    @ViewBuilder
    private func imageLayer(size: CGSize) -> some View {
        if let url {
            if isVideo {
                if let videoPreview {
                    Image(nsImage: videoPreview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Design.inkTertiary)
                        .frame(width: size.width, height: size.height)
                }
            } else if let image = WallpaperImageStore.cachedImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                emptyState
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        Button(action: onPick) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Design.surfaceRaised)
                        .frame(width: 32, height: 32)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Design.inkSecondary)
                }

                VStack(spacing: 2) {
                    Text("Select \(target.title)")
                        .font(Design.font(11, weight: .bold))
                        .foregroundStyle(Design.ink)

                    Text("Drop file or click to select")
                        .font(Design.font(9, weight: .regular))
                        .foregroundStyle(Design.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.surface)
        }
        .buttonStyle(.plain)
        .pointerOnHover()
    }

    private func reloadPreview() async {
        guard let url else { return }
        if isVideo {
            videoPreview = nil
            let preferredID = url.deletingPathExtension().lastPathComponent
            if let poster = await SystemWallpaperCatalog.posterFrame(
                forVideoAt: url,
                preferredID: preferredID
            ) {
                withAnimation(.easeOut(duration: 0.25)) {
                    videoPreview = NSImage(contentsOf: poster)
                }
            }
        } else {
            WallpaperImageStore.load(url) { image in
                if image != nil {
                    DispatchQueue.main.async {
                        cacheGeneration += 1
                    }
                }
            }
        }
    }
}

// MARK: - Real Full-Screen macOS Lock Screen Preview Manager

@MainActor
final class LockScreenPreviewManager: NSObject {
    static let shared = LockScreenPreviewManager()

    private var previewWindows: [NSWindow] = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isDismissing = false

    func show(url: URL) {
        dismissImmediately()

        isDismissing = false
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.alphaValue = 0.0

            let hostingView = NSHostingView(
                rootView: FullScreenLockScreenView(imageURL: url) { [weak self] in
                    self?.dismiss()
                }
            )
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView = hostingView
            window.orderFrontRegardless()
            previewWindows.append(window)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
        }

        // Dismiss on any keyboard press or mouse click anywhere
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
            return nil
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard !isDismissing, !previewWindows.isEmpty else { return }
        isDismissing = true

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        let windowsToClose = previewWindows
        previewWindows.removeAll()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in windowsToClose {
                window.animator().alphaValue = 0.0
            }
        } completionHandler: {
            for window in windowsToClose {
                window.orderOut(nil)
            }
        }
    }

    private func dismissImmediately() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        for window in previewWindows {
            window.orderOut(nil)
        }
        previewWindows.removeAll()
        isDismissing = false
    }
}

// MARK: - Full-Screen Authentic macOS Lock Screen View

struct FullScreenLockScreenView: View {
    let imageURL: URL
    let onDismiss: () -> Void

    @State private var currentTime = Date()
    @State private var player: AVPlayer?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isVideo: Bool {
        ["mov", "mp4", "m4v"].contains(imageURL.pathExtension.lowercased())
    }

    private var userName: String {
        let full = NSFullUserName()
        return full.isEmpty ? NSUserName() : full
    }

    private var userAvatar: NSImage? {
        let avatarURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".accountphoto")
        if let data = try? Data(contentsOf: avatarURL), let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Full Screen Edge-to-Edge Wallpaper
            backgroundLayer
                .ignoresSafeArea()

            // Subtle Lock Screen Dimming Gradient
            LinearGradient(
                colors: [
                    Color.black.opacity(0.20),
                    Color.clear,
                    Color.black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Top Status Bar (Wi-Fi, Battery, Control Center)
            VStack {
                HStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "wifi")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Image(systemName: "battery.100")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                Spacer()
            }

            // Real Lock Screen Center Layout
            VStack(spacing: 0) {
                Spacer()

                // Time & Date
                VStack(spacing: 4) {
                    Text(timeString(from: currentTime))
                        .font(Design.font(84, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.98))
                        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 2)

                    Text(dateString(from: currentTime))
                        .font(Design.font(17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 1)
                }

                Spacer()

                // User Profile & Password Pill
                VStack(spacing: 16) {
                    if let userAvatar {
                        Image(nsImage: userAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))
                            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 2)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))

                            Image(systemName: "person.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 2)
                    }

                    Text(userName)
                        .font(Design.font(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 1)

                    HStack(spacing: 8) {
                        Text("Enter Password")
                            .font(Design.font(12, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.65))

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(width: 210)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, y: 2)

                    HStack(spacing: 5) {
                        Image(systemName: "touchid")
                            .font(.system(size: 11.5))
                        Text("Touch ID or Enter Password")
                            .font(Design.font(11, weight: .regular))
                    }
                    .foregroundStyle(Color.white.opacity(0.70))
                }

                Spacer()

                // Subtle exit hint at bottom
                Text("Press any key or click anywhere to exit")
                    .font(Design.font(11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .onReceive(timer) { input in
            currentTime = input
        }
        .onAppear {
            setupVideoPlayerIfNeeded()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if isVideo {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                Color.black
            }
        } else if let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.black
        }
    }

    private func setupVideoPlayerIfNeeded() {
        guard isVideo else { return }
        let player = AVPlayer(url: imageURL)
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
        self.player = player
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
