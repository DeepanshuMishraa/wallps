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
        case .desktop: return "Visible when signed in"
        case .login: return "Visible on lock screen"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "macbook"
        case .login: return "lock.display"
        }
    }

    var chipLabel: String {
        switch self {
        case .desktop: return "DESKTOP"
        case .login: return "LOCK SCREEN"
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
            titleBar
            Rectangle().fill(Design.hairline).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    cardsSection
                    generalSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            statusBar
        }
        .background(Design.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 640, minHeight: 580, idealHeight: 640)
        .background(WindowChromeConfigurator())
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch pendingTarget {
            case .desktop: desktopImage = url
            case .login: loginImage = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setWallpapers)) { _ in
            applyWallpapers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWallpaperPreviews)) { _ in
            didAutoReapply = false
            autoReapplySavedChoices()
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
            Text("Wallps starts hidden at every login and keeps swapping your desktop and lock screen wallpapers automatically. You can turn this off anytime.")
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

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 9) {
            StatusDot(filled: true, isGlowing: true)
            Text("WALLPS")
                .font(Design.mono(11, .bold))
                .tracking(2.2)
                .foregroundStyle(Design.ink)
            Text("v\(appVersion)")
                .font(Design.mono(9.5, .medium))
                .foregroundStyle(Design.inkTertiary)

            Spacer()

            GhostIconButton(
                symbol: "sparkles.rectangle.stack",
                help: "Browse Apple system wallpapers & aerials",
                badge: "BROWSE"
            ) {
                showingBrowser = true
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 16)
        .frame(height: 48)
    }

    // MARK: - Sections

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Wallpapers")
            wallpaperCard(target: .desktop, image: desktopImage)
            wallpaperCard(target: .login, image: loginImage)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("General")
            optionRow(
                icon: "pause.fill",
                title: "Pause Wallps",
                detail: isPaused
                    ? "System Settings has full control."
                    : "Changes from System Settings are adopted as your desktop wallpaper.",
                binding: $isPaused
            )
            .onChange(of: isPaused) { paused in
                WallpaperSwitcher.shared.isPaused = paused
                if !paused {
                    syncCardsFromSwitcher()
                }
            }

            optionRow(
                icon: "power",
                title: "Launch at Login",
                detail: "Starts hidden and keeps the lock-screen swap armed after reboot.",
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
        }
    }

    private func optionRow(
        icon: String,
        title: String,
        detail: String,
        binding: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Design.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Design.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.mono(11.5, .medium))
                    .foregroundStyle(Design.ink)
                Text(detail)
                    .font(Design.mono(9.5, .regular))
                    .foregroundStyle(Design.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(PillToggleStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
    }

    // MARK: - Cards & status

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

    private func autoReapplySavedChoices() {
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

    private func wallpaperCard(target: ImportTarget, image: URL?) -> some View {
        WallpaperCardView(
            target: target,
            url: image,
            onPick: { chooseImage(for: target) },
            onAcceptImage: { url in
                switch target {
                case .desktop: desktopImage = url
                case .login: loginImage = url
                }
            }
        )
    }

    private var statusText: String {
        if let message = statusMessage {
            return message.uppercased()
        }
        if isPaused {
            return "PAUSED — SYSTEM SETTINGS IN CONTROL"
        }
        return "LOCK YOUR MAC (⌃⌘Q) TO PREVIEW"
    }

    private var statusBar: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Design.hairline).frame(height: 1)
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    StatusDot(filled: statusMessage != nil && !statusIsError, isGlowing: statusMessage != nil && !statusIsError)
                    Text(statusText)
                        .font(Design.mono(9.5, .medium))
                        .tracking(0.8)
                        .foregroundStyle(statusIsError ? Color(red: 1.0, green: 0.45, blue: 0.45) : Design.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                PrimaryActionButton(
                    title: isApplying ? "Applying" : "Set Wallpapers",
                    isLoading: isApplying,
                    keyEquivalent: .return
                ) {
                    applyWallpapers()
                }
                .disabled(desktopImage == nil || loginImage == nil || isApplying || isPaused)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusMessage)
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

// MARK: - Wallpaper Card View

private struct WallpaperCardView: View {
    let target: ImportTarget
    let url: URL?
    let onPick: () -> Void
    let onAcceptImage: (URL) -> Void

    @State private var cacheGeneration = 0
    @State private var hovering = false
    @State private var dropping = false
    @State private var videoPreview: NSImage?

    private var isVideo: Bool {
        ["mov", "mp4", "m4v"].contains(url?.pathExtension.lowercased() ?? "")
    }

    var body: some View {
        Button(action: onPick) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Design.surface)

                GeometryReader { geo in
                    imageLayer(size: geo.size)
                }

                if url != nil {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.65),
                            Color.clear,
                            Color.black.opacity(0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                foregroundControls
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        dropping ? Color.white : (hovering ? Color.white.opacity(0.35) : Design.hairline),
                        lineWidth: dropping ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
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

    private var foregroundControls: some View {
        VStack(spacing: 0) {
            headerRow
            Spacer()
            footerRow
        }
        .padding(10)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: target.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(target.chipLabel)
                    .font(Design.mono(9, .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

            if isVideo {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("LIVE")
                        .font(Design.mono(8.5, .bold))
                        .tracking(1.0)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }

            Spacer()

            editPencilButton
        }
    }

    private var editPencilButton: some View {
        HStack(spacing: 5) {
            Image(systemName: url == nil ? "plus" : "pencil")
                .font(.system(size: 11, weight: .bold))
            Text(url == nil ? "CHOOSE" : "EDIT")
                .font(Design.mono(9, .bold))
                .tracking(1.0)
        }
        .foregroundStyle(hovering ? Color.black : Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(hovering ? Color.white : Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hovering ? Color.white : Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: hovering ? Color.white.opacity(0.2) : Color.clear, radius: 6, y: 1)
    }

    private var footerRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let url {
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.inkSecondary)
                    Text(url.lastPathComponent)
                        .font(Design.mono(9.5, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: target.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Design.inkTertiary)
            VStack(spacing: 2) {
                Text("CHOOSE \(target.chipLabel) IMAGE")
                    .font(Design.mono(10, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Design.inkSecondary)
                Text("Drop file here or click to choose")
                    .font(Design.mono(9, .regular))
                    .foregroundStyle(Design.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
