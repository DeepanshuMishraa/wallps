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

    var symbol: String {
        switch self {
        case .desktop: return "menubar.dock.rectangle"
        case .login: return "lock"
        }
    }
}

/// What the footer tells the user about the current pair. One case at a time,
/// derived from state, so the message and the Apply button never disagree.
private enum SyncStatus {
    case incomplete
    case paused
    case applying
    case pending
    case active

    var message: String {
        switch self {
        case .incomplete: return "Pick a wallpaper for each screen"
        case .paused: return "Paused. Your lock screen matches your desktop."
        case .applying: return "Applying…"
        case .pending: return "Ready to apply"
        case .active: return "Active. Each screen keeps its own wallpaper."
        }
    }

    var color: Color {
        switch self {
        case .incomplete, .applying: return Design.inkTertiary
        case .paused: return Design.warning
        case .pending: return Color.accentColor
        case .active: return Design.success
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
    @State private var hideDockIcon = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerBar

                HStack(alignment: .previewCenter, spacing: 14) {
                    wallpaperViewport(target: .desktop, image: desktopImage)
                    swapButton
                    wallpaperViewport(target: .login, image: loginImage)
                }
                .padding(.horizontal, 28)
                .frame(maxHeight: .infinity)

                footerBar
            }

            if let message = toastMessage {
                WallpsToast(message: message)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            toastMessage = nil
                        }
                    }
            }

            if showingSettings {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(99)
                    .onTapGesture { setSettingsVisible(false) }

                HStack {
                    Spacer()
                    settingsCard
                        .padding(.trailing, 16)
                        .padding(.top, 50)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                .zIndex(100)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 440, idealHeight: 500)
        .background {
            WindowChromeConfigurator()
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .movie, .mpeg4Movie, .quickTimeMovie],
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
        .onReceive(NotificationCenter.default.publisher(for: .openWallpaperBrowser)) { _ in
            setSettingsVisible(false)
            showingBrowser = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .swapWallpapers)) { _ in
            // The menu swaps what is applied, not unsaved edits in the window.
            syncCardsFromSwitcher()
            swapWallpapers()
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
            "Open Wallps at login?",
            isPresented: $showingLoginPrompt,
            titleVisibility: .visible
        ) {
            Button("Open at Login") {
                Task {
                    do {
                        try LoginItemManager.enable()
                    } catch {
                        launchAtLogin = false
                        alert = WallpaperService.AlertMessage(
                            title: "Couldn't turn on Launch at Login",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            Button("Not Now", role: .cancel) {
                launchAtLogin = false
            }
        } message: {
            Text("Wallps starts quietly in the menu bar, so your lock screen keeps its own wallpaper after every restart.")
        }
        .onAppear {
            FontRegistrar.registerBundledFonts()
            MenuBarManager.shared.attachToMainWindowIfNeeded()
            isPaused = WallpaperSwitcher.shared.isPaused
            launchAtLogin = LoginItemManager.isEnabled
            hideDockIcon = DockIconManager.isHidden
            autoReapplySavedChoices()
        }
    }

    // MARK: - Header

    /// No title: the two screens are the content. Actions sit on the trailing
    /// edge, clear of the traffic lights.
    private var headerBar: some View {
        HStack(spacing: 8) {
            Spacer()

            ToolbarButton(
                symbol: "photo.on.rectangle.angled",
                title: "Browse",
                help: "Browse Apple wallpapers and live aerials"
            ) {
                showingBrowser = true
            }

            ToolbarButton(
                symbol: "gearshape",
                help: "Settings",
                isActive: showingSettings
            ) {
                setSettingsVisible(!showingSettings)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - Swap

    private var swapButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                swapWallpapers()
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Design.inkSecondary)
                .frame(width: 30, height: 30)
                .tintedGlassSurface(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .disabled(desktopImage == nil && loginImage == nil)
        .help("Swap the desktop and lock screen wallpapers")
        .accessibilityLabel("Swap desktop and lock screen")
        .alignmentGuide(.previewCenter) { $0[VerticalAlignment.center] }
    }

    /// Swaps the two selections. Like any edit, it takes effect on Apply.
    private func swapWallpapers() {
        (desktopImage, loginImage) = (loginImage, desktopImage)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(syncStatus.color)
                    .frame(width: 7, height: 7)
                Text(syncStatus.message)
                    .font(Design.font(12))
                    .foregroundStyle(Design.inkSecondary)
                    .lineLimit(1)
            }
            .animation(.easeOut(duration: 0.15), value: syncStatus)

            Spacer(minLength: 12)

            if isApplying {
                ProgressView()
                    .controlSize(.small)
            }

            if isPaused {
                Button {
                    isPaused = false
                    WallpaperSwitcher.shared.isPaused = false
                    syncCardsFromSwitcher()
                } label: {
                    Text("Resume").font(Design.font(13, weight: .medium))
                }
                .controlSize(.large)
            } else {
                Button {
                    applyWallpapers()
                } label: {
                    Text("Apply")
                        .font(Design.font(13, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(syncStatus != .pending)
                .help("Apply both wallpapers (⌘↩)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private var syncStatus: SyncStatus {
        if isApplying { return .applying }
        if isPaused { return .paused }
        guard desktopImage != nil, loginImage != nil else { return .incomplete }
        return isPairApplied ? .active : .pending
    }

    // MARK: - Settings

    private func setSettingsVisible(_ visible: Bool) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showingSettings = visible
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsRow(
                "Launch at login",
                detail: "Keeps everything working after a restart",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { enabled in
                guard enabled else {
                    Task { try? LoginItemManager.disable() }
                    return
                }
                guard !LoginItemManager.isEnabled else { return }
                showingLoginPrompt = true
            }

            Divider().padding(.vertical, 10)

            settingsRow(
                "Pause switching",
                detail: "Your lock screen shows the desktop wallpaper",
                isOn: $isPaused
            )
            .onChange(of: isPaused) { paused in
                guard WallpaperSwitcher.shared.isPaused != paused else { return }
                WallpaperSwitcher.shared.isPaused = paused
                if !paused {
                    syncCardsFromSwitcher()
                }
            }

            Divider().padding(.vertical, 10)

            settingsRow(
                "Hide Dock icon",
                detail: "Find Wallps in the menu bar instead",
                isOn: $hideDockIcon
            )
            .onChange(of: hideDockIcon) { hidden in
                DockIconManager.setHidden(hidden)
                if hidden {
                    DispatchQueue.main.async {
                        MenuBarManager.shared.showMainWindow()
                    }
                }
            }

            Divider().padding(.vertical, 10)

            Text("Version \(appVersion)")
                .font(Design.font(11))
                .foregroundStyle(Design.inkTertiary)
        }
        .padding(16)
        .frame(width: 300)
        .tintedGlassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    private func settingsRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.font(13))
                    .foregroundStyle(Design.ink)
                Text(detail)
                    .font(Design.font(11))
                    .foregroundStyle(Design.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
    }

    // MARK: - Previews

    private func wallpaperViewport(target: ImportTarget, image: URL?) -> some View {
        WallpaperViewportView(
            target: target,
            url: image,
            onPick: { chooseImage(for: target) },
            onBrowse: { showingBrowser = true },
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
                _ = try await WallpaperSwitcher.shared.applyAndArm(
                    desktop: DesktopSource.infer(for: desktopImage),
                    login: LoginSource.infer(for: loginImage),
                    legacyInstall: true
                )
                let liveLock = LoginSource.infer(for: loginImage) == .video(loginImage)
                MenuBarManager.shared.reassertMainWindowIfVisible()

                toastTask?.cancel()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    toastMessage = liveLock ? "Your live lock screen is on" : "Both wallpapers are set"
                }
                toastTask = Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        toastMessage = nil
                    }
                }
            } catch {
                alert = WallpaperService.AlertMessage(title: "Couldn't apply your wallpapers", message: error.localizedDescription)
            }
            isApplying = false
        }
    }

    private var isPairApplied: Bool {
        guard let desktopImage, let loginImage else { return false }
        let savedDesktop = WallpaperSwitcher.shared.savedDesktopURL
        let savedLogin = WallpaperSwitcher.shared.savedLoginURL
        return desktopImage.standardizedFileURL == savedDesktop?.standardizedFileURL &&
               loginImage.standardizedFileURL == savedLogin?.standardizedFileURL
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
        // AppDelegate already re-applied the saved pair at launch; doing it
        // again here restarted the wallpaper services a second time (visible
        // flicker / lock-screen reset). Only an explicit Refresh re-applies.
        guard force || !WallpaperSwitcher.shared.hasReappliedAtLaunch else { return }
        Task {
            isApplying = true
            do {
                _ = try await WallpaperSwitcher.shared.applyAndArm(
                    desktop: DesktopSource.infer(for: savedDesktop),
                    login: LoginSource.infer(for: savedLogin),
                    legacyInstall: false
                )
            } catch {}
            isApplying = false
        }
    }
}

// MARK: - Screen Preview

/// One screen (desktop or lock screen) rendered as a miniature of the real
/// thing, so the two are told apart at a glance: the desktop gets a menu bar
/// and Dock, the lock screen gets the clock.
private struct WallpaperViewportView: View {
    let target: ImportTarget
    let url: URL?
    let onPick: () -> Void
    let onBrowse: () -> Void
    let onAcceptImage: (URL) -> Void
    let onClear: () -> Void

    @State private var cacheGeneration = 0
    @State private var dropping = false
    @State private var hovering = false
    @State private var videoPreview: NSImage?

    private var isVideo: Bool {
        ["mov", "mp4", "m4v"].contains(url?.pathExtension.lowercased() ?? "")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Design.previewRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
                .alignmentGuide(.previewCenter) { $0[VerticalAlignment.center] }
            caption
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            if url != nil {
                GeometryReader { geo in
                    imageLayer(size: geo.size)
                }
                screenChrome
                    .allowsHitTesting(false)

                OverlayButton(title: "Change", symbol: "photo", action: onPick)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .opacity(hovering && !dropping ? 1 : 0)
            } else {
                emptyState
            }

            if dropping {
                dropOverlay
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                dropping ? Color.accentColor : Design.hairline,
                lineWidth: dropping ? 2 : 1
            )
        )
        .shadow(color: Color.black.opacity(url == nil ? 0 : 0.14), radius: 14, y: 6)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: dropping)
        .contextMenu { actions }
        .onDrop(
            of: [.fileURL, .image, .movie, .heic],
            isTargeted: $dropping
        ) { providers in
            guard let provider = providers.first else { return false }
            Task {
                if let url = await Self.resolveDroppedFile(provider) {
                    await MainActor.run { onAcceptImage(url) }
                }
            }
            return true
        }
        .task(id: url) {
            await reloadPreview()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(target.title) wallpaper")
    }

    @ViewBuilder
    private var screenChrome: some View {
        switch target {
        case .desktop:
            DesktopChrome()
        case .login:
            LockScreenChrome()
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.18)
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                Text("Drop to use as \(target.title)")
                    .font(Design.font(12, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .tintedGlassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        Button(action: onPick) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Design.inkSecondary)
                Text("Choose an image or video")
                    .font(Design.font(12.5, weight: .medium))
                    .foregroundStyle(Design.ink)
                Text("or drag one here")
                    .font(Design.font(11))
                    .foregroundStyle(Design.inkTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hovering ? Design.hairline : Design.well)
            .overlay(
                shape
                    .inset(by: 6)
                    .strokeBorder(Design.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerOnHover()
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
                    ZStack {
                        Design.well
                        ProgressView().controlSize(.small)
                    }
                    .frame(width: size.width, height: size.height)
                }
            } else if let image = WallpaperImageStore.cachedImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Design.well
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    // MARK: Caption

    private var caption: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(target.title)
                        .font(Design.display(18))
                        .foregroundStyle(Design.ink)
                    if isVideo {
                        Text("Live")
                            .font(Design.font(10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                Text(url.map(Self.displayName) ?? "Nothing chosen yet")
                    .font(Design.font(11.5))
                    .foregroundStyle(Design.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url?.path ?? "")
            }

            Spacer(minLength: 0)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.inkTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options")
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var actions: some View {
        Button("Choose File…", action: onPick)
        Button("Browse Apple Wallpapers…", action: onBrowse)
        if let url {
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Remove", role: .destructive, action: onClear)
        }
    }

    /// File name without extension; Apple's catalog files are already named.
    private static func displayName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
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

    /// Resolves a dragged item to a file URL. Finder files arrive as file URLs;
    /// images/videos dragged from browsers or other apps arrive as raw data and
    /// are persisted into the Wallps Drops folder.
    private static func resolveDroppedFile(_ provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await withCheckedContinuation({ continuation in
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: object as? URL)
                }
            }) {
                return url.standardizedFileURL
            }
            if let data = await loadData(provider, forTypeIdentifier: UTType.fileURL.identifier),
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url.standardizedFileURL
            }
        }

        let mediaType = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { $0.conforms(to: .image) || $0.conforms(to: .movie) }
        guard let mediaType,
              let data = await loadData(provider, forTypeIdentifier: mediaType.identifier) else {
            return nil
        }
        let isVideo = mediaType.conforms(to: .movie)
        let ext = mediaType.preferredFilenameExtension ?? (isVideo ? "mov" : "png")
        return persistDroppedData(data, ext: ext)
    }

    private static func loadData(_ provider: NSItemProvider, forTypeIdentifier typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func persistDroppedData(_ data: Data, ext: String) -> URL? {
        let directory = SystemWallpaperCatalog.dropsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("drop-\(UUID().uuidString.prefix(8)).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

extension VerticalAlignment {
    /// Vertical centre of the screen previews, so the swap button sits
    /// between the images rather than between image-plus-caption blocks.
    private enum PreviewCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let previewCenter = VerticalAlignment(PreviewCenter.self)
}

/// Miniature menu bar and Dock drawn over the desktop preview.
private struct DesktopChrome: View {
    var body: some View {
        GeometryReader { geo in
            let barHeight = max(6, geo.size.height * 0.045)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: barHeight)
                    .overlay(alignment: .leading) {
                        HStack(spacing: barHeight * 0.8) {
                            Image(systemName: "applelogo")
                            ForEach(0..<4, id: \.self) { _ in
                                Capsule().frame(width: barHeight * 2.2, height: barHeight * 0.3)
                            }
                        }
                        .font(.system(size: barHeight * 0.6))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.leading, barHeight)
                    }

                Spacer()

                RoundedRectangle(cornerRadius: barHeight * 0.8, style: .continuous)
                    .fill(Color.white.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: barHeight * 0.8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .frame(width: geo.size.width * 0.42, height: barHeight * 2.4)
                    .padding(.bottom, barHeight * 0.7)
            }
        }
    }
}

/// Lock-screen clock drawn over the lock screen preview, kept to the minute.
private struct LockScreenChrome: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.everyMinute) { context in
                VStack(spacing: 0) {
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(Design.font(geo.size.height * 0.055, weight: .medium))
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(Design.display(geo.size.height * 0.24))
                        .monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
                .frame(maxWidth: .infinity)
                .padding(.top, geo.size.height * 0.09)
            }
        }
    }
}

#Preview {
    ContentView()
}
