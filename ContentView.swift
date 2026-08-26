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
            // Left Control Sidebar (Clean, Unified)
            leftSidebar
                .frame(width: 240)
                .background(Design.surface)

            // Right Stage Area (Perfect spacing, clean alignment)
            VStack(spacing: 0) {
                topBar
                mainStage
                bottomStatusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.background)
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 480, idealHeight: 560)
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

    // MARK: - Left Sidebar

    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Identity
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Wallps")
                        .font(Design.font(16, weight: .bold))
                        .foregroundStyle(Design.ink)

                    Text("v\(appVersion)")
                        .font(Design.font(9, weight: .medium))
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
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            Divider()
                .background(Design.hairline)

            // Settings Section
            VStack(alignment: .leading, spacing: 20) {
                Text("SETTINGS")
                    .font(Design.font(9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Design.inkTertiary)
                    .padding(.top, 24)

                // Launch at Login
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch on boot")
                            .font(Design.font(11, weight: .semibold))
                            .foregroundStyle(Design.ink)
                        Text("Start automatically")
                            .font(Design.font(9.5, weight: .regular))
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

                // Pause sync
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause switching")
                            .font(Design.font(11, weight: .semibold))
                            .foregroundStyle(Design.ink)
                        Text("Deactivate engine")
                            .font(Design.font(9.5, weight: .regular))
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
            .padding(.horizontal, 24)

            Spacer()

            // Action Buttons
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
            .padding(16)
        }
        .overlay(
            HStack {
                Spacer()
                Rectangle()
                    .fill(Design.hairline)
                    .frame(width: 1)
            }
        )
    }

    // MARK: - Right Top Bar

    private var topBar: some View {
        HStack {
            Text("STUDIO WORKSPACE")
                .font(Design.font(9.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Design.inkTertiary)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(height: 56)
        .overlay(
            VStack {
                Spacer()
                Rectangle()
                    .fill(Design.hairline)
                    .frame(height: 1)
            }
        )
    }

    // MARK: - Right Main Stage

    private var mainStage: some View {
        HStack(spacing: 24) {
            wallpaperViewport(target: .desktop, image: desktopImage)
                .frame(maxWidth: .infinity)

            wallpaperViewport(target: .login, image: loginImage)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
    }

    // MARK: - Right Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            StatusDot(
                filled: true,
                isGlowing: isApplying,
                customColor: statusIsError ? Design.error : (isPaused ? Design.inkTertiary : (isApplying ? Design.accent : Design.success))
            )

            Text(statusText)
                .font(Design.font(10, weight: .medium))
                .foregroundStyle(statusIsError ? Design.error : Design.inkSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(height: 40)
        .overlay(
            VStack {
                Rectangle()
                    .fill(Design.hairline)
                    .frame(height: 1)
                Spacer()
            }
        )
    }

    private func wallpaperViewport(target: ImportTarget, image: URL?) -> some View {
        WallpaperViewportView(
            target: target,
            url: image,
            onPick: { chooseImage(for: target) },
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
            return "Sync is paused. Desktop and Lock Screen will not automatically sync."
        }
        return "System paired. Lock your screen (⌃⌘Q) to see the lock screen wallpaper."
    }

    private func chooseImage(for target: ImportTarget) {
        pendingTarget = target
        isImporting = true
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

#Preview {
    ContentView()
}
