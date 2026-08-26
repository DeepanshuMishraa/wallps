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
        case .login: return "Lock screen background"
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
    @State private var alert: WallpaperService.AlertMessage?
    @State private var launchAtLogin = false
    @State private var showingLoginPrompt = false
    @State private var didAutoReapply = false
    @State private var isPaused = false
    @State private var showingBrowser = false
    @State private var showingSettings = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerBar

                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            displayStage(availableWidth: geo.size.width)

                            // Centered Apply Button directly below wallpaper cards
                            HStack {
                                Spacer()
                                PrimaryActionButton(
                                    title: isApplying ? "Applying…" : "Apply Wallpapers (⌘↵)",
                                    isLoading: isApplying,
                                    keyEquivalent: .return
                                ) {
                                    applyWallpapers()
                                }
                                .disabled(desktopImage == nil || loginImage == nil || isApplying || isPaused)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(minHeight: geo.size.height, alignment: .center)
                    }
                }
            }
            .background(Design.background)

            // Minimal Center-Top Toast Notification
            if let message = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Design.success)

                    Text(message.uppercased())
                        .font(Design.font(9.5, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Design.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Design.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Design.hairlineStrong, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
                .padding(.top, 12)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                        removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92))
                    )
                )
                .zIndex(200)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        toastMessage = nil
                    }
                }
            }

            // Smooth Settings Dropdown Overlay
            if showingSettings {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showingSettings = false
                        }
                    }

                VStack {
                    HStack {
                        Spacer()
                        settingsCard
                            .padding(.trailing, 20)
                            .padding(.top, 54)
                    }
                    Spacer()
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing))
                    )
                )
                .zIndex(100)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460, idealHeight: 520)
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

    // MARK: - Header Bar (No Bottom Border, No Green Dot)

    private var headerBar: some View {
        HStack(spacing: 12) {
            // App Title & Version (No green dot)
            HStack(spacing: 6) {
                Text("Wallps")
                    .font(Design.font(14, weight: .bold))
                    .foregroundStyle(Design.ink)

                Text("v\(appVersion)")
                    .font(Design.font(9.5, weight: .medium))
                    .foregroundStyle(Design.inkTertiary)
            }

            Spacer()

            // Header Actions
            HStack(spacing: 8) {
                GhostIconButton(
                    symbol: "sparkles.rectangle.stack",
                    text: "Apple Catalog",
                    help: "Browse Apple system wallpapers & dynamic live aerials"
                ) {
                    showingBrowser = true
                }

                // Settings Toggle Button with Smooth Popover
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showingSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(showingSettings ? Design.ink : Design.inkSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(showingSettings ? Design.surfaceRaised : Design.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(showingSettings ? Design.hairlineStrong : Design.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .background(Design.background)
    }

    // MARK: - Settings Dropdown Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PREFERENCES")
                    .font(Design.font(9.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Design.inkTertiary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showingSettings = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Design.inkTertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }

            VStack(spacing: 10) {
                // Launch on boot
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch on boot")
                            .font(Design.font(11, weight: .semibold))
                            .foregroundStyle(Design.ink)
                        Text("Starts silently in background")
                            .font(Design.font(9.5, weight: .regular))
                            .foregroundStyle(Design.inkTertiary)
                    }
                    Spacer(minLength: 16)
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

                Divider()
                    .background(Design.hairline)

                // Pause sync
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause sync")
                            .font(Design.font(11, weight: .semibold))
                            .foregroundStyle(Design.ink)
                        Text("Temporarily suspend engine")
                            .font(Design.font(9.5, weight: .regular))
                            .foregroundStyle(Design.inkTertiary)
                    }
                    Spacer(minLength: 16)
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
        .padding(16)
        .frame(width: 270)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Design.hairlineStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 16, y: 8)
    }

    // MARK: - Display Stage (Responsive 2-Viewport Grid)

    @ViewBuilder
    private func displayStage(availableWidth: CGFloat) -> some View {
        if availableWidth >= 520 {
            HStack(spacing: 20) {
                wallpaperViewport(target: .desktop, image: desktopImage)
                    .frame(maxWidth: .infinity)

                wallpaperViewport(target: .login, image: loginImage)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 20) {
                wallpaperViewport(target: .desktop, image: desktopImage)
                wallpaperViewport(target: .login, image: loginImage)
            }
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

    private func chooseImage(for target: ImportTarget) {
        pendingTarget = target
        isImporting = true
    }

    private func applyWallpapers() {
        guard let desktopImage, let loginImage else { return }
        Task {
            isApplying = true
            do {
                _ = try await WallpaperService.apply(login: loginImage)
                WallpaperSwitcher.shared.arm(desktop: desktopImage, login: loginImage)

                // Trigger Minimal Top Center Toast
                toastTask?.cancel()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    toastMessage = "Wallpapers applied"
                }
                toastTask = Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        toastMessage = nil
                    }
                }
            } catch {
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
            do {
                _ = try await WallpaperService.apply(login: savedLogin, legacyInstall: false)
                WallpaperSwitcher.shared.arm(desktop: savedDesktop, login: savedLogin)
            } catch {}
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
        VStack(alignment: .leading, spacing: 10) {
            // Viewport Header
            HStack(spacing: 8) {
                Image(systemName: target.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.inkSecondary)

                Text(target.title.uppercased())
                    .font(Design.font(11, weight: .bold))
                    .tracking(1.2)
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

            // Display Frame (16:10 aspect ratio)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Design.surface)

                GeometryReader { geo in
                    imageLayer(size: geo.size)
                }

                if url != nil {
                    // Ambient gradient overlay for action buttons contrast
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Floating Glass Actions Bar
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: onClear) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("CLEAR")
                                        .font(Design.font(9.5, weight: .bold))
                                        .tracking(0.6)
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()

                            Spacer()

                            Button(action: onPick) {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("CHANGE")
                                        .font(Design.font(9.5, weight: .bold))
                                        .tracking(0.6)
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .pointerOnHover()
                        }
                        .padding(10)
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
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
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
        .padding(14)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
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
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Design.surfaceRaised)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Design.inkSecondary)
                }

                VStack(spacing: 3) {
                    Text("Select \(target.title)")
                        .font(Design.font(11.5, weight: .bold))
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
