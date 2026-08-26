import AppKit
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
        case .desktop: return "Active workspace wallpaper"
        case .login: return "Login and lock display wallpaper"
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
        VStack(spacing: 0) {
            headerBar

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        wallpapersSection(availableWidth: geo.size.width)
                        settingsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(Design.background)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 520, idealHeight: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                StatusDot(
                    filled: true,
                    isGlowing: !isPaused,
                    customColor: isPaused ? Design.inkTertiary : (statusIsError ? Design.error : Design.success)
                )

                Text("Wallps")
                    .font(Design.font(13, weight: .bold))
                    .foregroundStyle(Design.ink)

                Text("v\(appVersion)")
                    .font(Design.font(10, weight: .medium))
                    .foregroundStyle(Design.inkTertiary)
            }

            Spacer()

            GhostIconButton(
                symbol: "sparkles.rectangle.stack",
                text: "Apple Catalog",
                help: "Browse Apple system wallpapers and live aerials"
            ) {
                showingBrowser = true
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 20)
        .frame(height: 50)
    }

    // MARK: - Wallpapers Studio Section

    @ViewBuilder
    private func wallpapersSection(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("WALLPAPERS")
                    .font(Design.font(11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Design.inkTertiary)

                Spacer()
            }

            if availableWidth >= 540 {
                // Wide side-by-side viewports
                HStack(alignment: .top, spacing: 14) {
                    wallpaperViewport(target: .desktop, image: desktopImage)
                        .frame(maxWidth: .infinity)

                    wallpaperViewport(target: .login, image: loginImage)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Stacked viewports
                VStack(spacing: 14) {
                    wallpaperViewport(target: .desktop, image: desktopImage)
                    wallpaperViewport(target: .login, image: loginImage)
                }
            }

            actionBar
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                StatusDot(
                    filled: true,
                    isGlowing: isApplying,
                    customColor: statusIsError ? Design.error : (isPaused ? Design.inkTertiary : (isApplying ? Design.accent : Design.success))
                )
                Text(statusText)
                    .font(Design.font(10.5, weight: .medium))
                    .foregroundStyle(statusIsError ? Design.error : Design.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            PrimaryActionButton(
                title: isApplying ? "Applying…" : "Apply Wallpapers (⌘↵)",
                isLoading: isApplying,
                keyEquivalent: .return
            ) {
                applyWallpapers()
            }
            .disabled(desktopImage == nil || loginImage == nil || isApplying || isPaused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Design.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusMessage)
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS")
                .font(Design.font(11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Design.inkTertiary)

            VStack(spacing: 10) {
                settingRow(
                    icon: "bolt.fill",
                    title: "Launch at login",
                    detail: "Starts quietly in the background on reboot to preserve lock screen pairing.",
                    binding: $launchAtLogin
                )
                .onAppear { launchAtLogin = LoginItemManager.isEnabled }
                .onChange(of: launchAtLogin) { enabled in
                    guard enabled else {
                        Task { try? LoginItemManager.disable() }
                        return
                    }
                    guard !LoginItemManager.isEnabled else { return }
                    showingLoginPrompt = true
                }

                settingRow(
                    icon: "pause.fill",
                    title: "Pause sync",
                    detail: isPaused
                        ? "Wallps is paused. System Settings has full control."
                        : "Active and monitoring. External wallpaper changes are automatically adopted.",
                    binding: $isPaused
                )
                .onChange(of: isPaused) { paused in
                    WallpaperSwitcher.shared.isPaused = paused
                    if !paused {
                        syncCardsFromSwitcher()
                    }
                }
            }
        }
    }

    private func settingRow(
        icon: String,
        title: String,
        detail: String,
        binding: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.ink)
                .frame(width: 30, height: 30)
                .background(Design.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Design.hairline, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.font(12, weight: .semibold))
                    .foregroundStyle(Design.ink)
                Text(detail)
                    .font(Design.font(10.5, weight: .regular))
                    .foregroundStyle(Design.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(PillToggleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
    }

    // MARK: - State Management

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
        guard !didAutoReapply else { return }
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
        // The launch-time pass (AppDelegate) already applied the saved pair;
        // this Task only runs when the window opens before that pass did,
        // or when the user explicitly asks to refresh.
        guard force || !WallpaperSwitcher.shared.hasReappliedAtLaunch else { return }
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
            return "Paused · System Settings in control"
        }
        return "Armed · Desktop and lock screen synced"
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
}

// MARK: - Minimalist Wallpaper Viewport

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
            // Viewport Header
            HStack(spacing: 6) {
                Image(systemName: target.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.inkSecondary)

                Text(target.title)
                    .font(Design.font(12, weight: .bold))
                    .foregroundStyle(Design.ink)

                if isVideo {
                    Text("LIVE AERIAL")
                        .font(Design.font(8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Design.accentInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Design.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer()

                if let url {
                    Text(url.lastPathComponent)
                        .font(Design.font(10, weight: .regular))
                        .foregroundStyle(Design.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
            }

            // Cinema Display Canvas (16:10 aspect ratio)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Design.surface)

                GeometryReader { geo in
                    imageLayer(size: geo.size)
                }

                if url != nil {
                    // Vignette gradient for text contrast
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.5)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Floating Glass Actions Bar
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
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()
                            .help("Remove wallpaper")

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
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()
                        }
                        .padding(8)
                    }
                }
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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

                    Text("Drop image or click to choose")
                        .font(Design.font(9.5, weight: .regular))
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
