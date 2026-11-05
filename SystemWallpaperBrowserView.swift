import AppKit
import SwiftUI

struct SystemWallpaperBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadCenter = WallpaperDownloadCenter.shared
    @State private var items: [SystemWallpaperItem] = []
    @State private var hasLoaded = false
    @State private var selectedCollection: WallpaperCollection?
    @State private var aerialMode: AerialMode = .live
    @State private var searchText = ""
    @State private var alert: WallpaperService.AlertMessage?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    enum AerialMode: String, CaseIterable, Identifiable {
        case live
        case still

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: return "Live"
            case .still: return "Still"
            }
        }
    }

    /// Sidebar groups: one section per macOS release, one for themed sets.
    private static let releaseCollections: [WallpaperCollection] = [
        .macOS27, .macOS26, .macOS15, .macOS14, .macOS13, .macOS12, .bigSur, .catalina, .mojave
    ]

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 320), spacing: 18, alignment: .top)]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)

            Divider()

            VStack(spacing: 0) {
                detailHeader
                grid
            }
        }
        .background {
            WindowChromeConfigurator()
                .ignoresSafeArea()
        }
        .frame(minWidth: 720, idealWidth: 900, maxWidth: .infinity, minHeight: 500, idealHeight: 620, maxHeight: .infinity)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            FontRegistrar.registerBundledFonts()
            loadItemsFast()
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                WallpsToast(message: message)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            toastMessage = nil
                        }
                    }
            }
        }
    }

    // MARK: - Filtering

    /// Collections that actually have wallpapers on this Mac, newest release first.
    private var collections: [WallpaperCollection] {
        let present = Set(items.map(\.collection))
        return WallpaperCollection.allCases.filter(present.contains)
    }

    /// The selected collection, falling back to the newest one available.
    private var activeCollection: WallpaperCollection? {
        selectedCollection.flatMap { collections.contains($0) ? $0 : nil } ?? collections.first
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Searching spans every collection; otherwise only the active one is shown.
    private var filteredItems: [SystemWallpaperItem] {
        guard !isSearching else {
            return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return items.filter { $0.collection == activeCollection }
    }

    private var showsAerialMode: Bool {
        filteredItems.contains { $0.kind == .aerial }
    }

    private func count(in collection: WallpaperCollection) -> Int {
        items.lazy.filter { $0.collection == collection }.count
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    sidebarSection("macOS", collections.filter(Self.releaseCollections.contains))
                    sidebarSection("Collections", collections.filter { !Self.releaseCollections.contains($0) })
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, _ entries: [WallpaperCollection]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Design.font(11, weight: .semibold))
                    .foregroundStyle(Design.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                ForEach(entries) { collection in
                    SidebarRow(
                        title: collection.title,
                        count: count(in: collection),
                        isSelected: !isSearching && collection == activeCollection
                    ) {
                        searchText = ""
                        selectedCollection = collection
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Design.inkTertiary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(Design.font(13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Design.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
    }

    // MARK: - Detail

    private var detailTitle: String {
        if isSearching { return "Results for “\(searchText)”" }
        return activeCollection?.title ?? "Wallpapers"
    }

    private var detailHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(detailTitle)
                .font(Design.display(26))
                .foregroundStyle(Design.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            if hasLoaded {
                Text("\(filteredItems.count)")
                    .font(Design.font(13))
                    .foregroundStyle(Design.inkTertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 12)

            if showsAerialMode {
                Picker("Aerials", selection: $aerialMode) {
                    ForEach(AerialMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Live plays the aerial as a video. Still uses a single frame.")
            }

            Button {
                dismiss()
            } label: {
                Text("Done").font(Design.font(13, weight: .medium))
            }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(filteredItems) { item in
                    SystemWallpaperCellView(
                        item: item,
                        downloadFraction: downloadCenter.progress[item.id],
                        isCurrentDesktop: appliedTo(item, saved: WallpaperSwitcher.shared.savedDesktopURL),
                        isCurrentLock: appliedTo(item, saved: WallpaperSwitcher.shared.savedLoginURL),
                        aerialModeTitle: item.kind == .aerial ? aerialMode.title : nil,
                        onUseDesktop: { await use(item, for: .desktop) },
                        onUseLock: { await use(item, for: .login) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .overlay {
            if !hasLoaded {
                ProgressView().controlSize(.small)
            } else if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: isSearching ? "magnifyingglass" : "photo.on.rectangle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Design.inkTertiary)
                    Text(isSearching ? "No wallpapers match “\(searchText)”" : "No wallpapers found on this Mac")
                        .font(Design.font(13, weight: .medium))
                        .foregroundStyle(Design.inkSecondary)
                }
            }
        }
    }

    // MARK: - Data

    private func loadItemsFast() {
        Task.detached(priority: .userInitiated) {
            let loaded = SystemWallpaperCatalog.items()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.items = loaded
                    self.hasLoaded = true
                }
            }
        }
    }

    /// Whether `item` is the currently applied wallpaper for desktop or lock.
    /// Aerials applied as stills live under the posters directory, so both the
    /// local content URL and the generated poster are considered. A live lock
    /// screen is armed to the system-aerial copy of the video, which keeps the
    /// item's asset identity (basename) even though the path differs — but only
    /// catalog-owned paths are trusted for basename matching, so a local
    /// wallpaper never lights up unrelated items.
    private func appliedTo(_ item: SystemWallpaperItem, saved: URL?) -> Bool {
        guard let saved = saved?.standardizedFileURL else { return false }
        let poster = SystemWallpaperCatalog.postersDirectory
            .appendingPathComponent("\(SystemWallpaperCatalog.sanitized(item.id))-poster.png")
        let candidates = [item.localContentURL, poster].compactMap { $0?.standardizedFileURL }
        if candidates.contains(saved) { return true }
        guard isCatalogOwned(saved) else { return false }
        let savedBase = saved.deletingPathExtension().lastPathComponent
        let itemBase = item.localContentURL?.deletingPathExtension().lastPathComponent ?? item.id
        return savedBase == itemBase
    }

    private func isCatalogOwned(_ url: URL) -> Bool {
        let ownedDirectories = [
            SystemWallpaperCatalog.postersDirectory,
            SystemWallpaperCatalog.aerialsDirectory,
            SystemWallpaperCatalog.dynamicDirectory,
            SystemWallpaperCatalog.appleAerialVideosDirectory
        ]
        let path = url.standardizedFileURL.path
        return ownedDirectories.contains { path.hasPrefix($0.standardizedFileURL.path) }
    }

    private func presentToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                toastMessage = nil
            }
        }
    }

    private enum ApplyTarget {
        case desktop
        case login
    }

    private func use(_ item: SystemWallpaperItem, for target: ApplyTarget) async {
        do {
            let wasDownloaded = item.localContentURL != nil
            let contentURL = try await downloadCenter.ensureDownloaded(item)

            // The item struct we hold is now stale: reload the catalog so the
            // downloaded badge appears without reopening the browser.
            withAnimation(.easeOut(duration: 0.15)) {
                items = SystemWallpaperCatalog.items(forceRefresh: true)
            }

            switch target {
            case .desktop:
                let source: DesktopSource
                if item.kind == .aerial && aerialMode == .live {
                    source = .video(contentURL)
                } else if item.kind == .aerial {
                    guard let poster = await SystemWallpaperCatalog.posterFrame(
                        forVideoAt: contentURL,
                        preferredID: item.id
                    ) else {
                        throw WallpaperDownloadError.extractionFailed(itemName: item.name)
                    }
                    source = .image(poster)
                } else {
                    source = .image(contentURL)
                }
                _ = try await WallpaperSwitcher.shared.applyAndArm(desktop: source, login: nil)
            case .login:
                if item.kind == .aerial && aerialMode == .live {
                    _ = try await WallpaperSwitcher.shared.applyAndArm(
                        desktop: nil,
                        login: .video(contentURL)
                    )
                } else {
                    let lockImageURL: URL
                    if item.kind == .aerial {
                        guard let poster = await SystemWallpaperCatalog.posterFrame(
                            forVideoAt: contentURL,
                            preferredID: item.id
                        ) else {
                            throw WallpaperDownloadError.extractionFailed(itemName: item.name)
                        }
                        lockImageURL = poster
                    } else {
                        lockImageURL = contentURL
                    }
                    _ = try await WallpaperSwitcher.shared.applyAndArm(desktop: nil, login: .image(lockImageURL))
                }
            }

            let targetName = target == .desktop ? "desktop" : "lock screen"
            MenuBarManager.shared.reassertMainWindowIfVisible()
            if wasDownloaded {
                presentToast("Your \(targetName) is set")
            } else {
                presentToast("Downloaded. Your \(targetName) is set")
            }

            NotificationCenter.default.post(name: .wallpsStateChanged, object: nil)
            withAnimation(.easeOut(duration: 0.15)) {
                items = SystemWallpaperCatalog.items(forceRefresh: true)
            }
        } catch {
            alert = WallpaperService.AlertMessage(
                title: "Could not use \"\(item.name)\"",
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Design.font(13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Design.ink)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Design.font(11))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Design.inkTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (hovering ? Design.well : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Grid Cell

private struct SystemWallpaperCellView: View {
    let item: SystemWallpaperItem
    let downloadFraction: Double?
    let isCurrentDesktop: Bool
    let isCurrentLock: Bool
    /// "Live" / "Still" for aerials; nil for pictures.
    let aerialModeTitle: String?
    let onUseDesktop: () async -> Void
    let onUseLock: () async -> Void

    @State private var thumbnailImage: NSImage?
    @State private var hovering = false
    @State private var applying = false

    private var isBusy: Bool { downloadFraction != nil || applying }
    private var isActive: Bool { isCurrentDesktop || isCurrentLock }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var detail: String {
        aerialModeTitle.map { "Aerial · \($0)" } ?? item.kind.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(Design.font(12.5, weight: .medium))
                    .foregroundStyle(Design.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(detail)
                    if !item.isDownloaded {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                }
                .font(Design.font(11))
                .foregroundStyle(Design.inkTertiary)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(item.isDownloaded ? item.name : "\(item.name). Downloads the first time you use it.")
        .contextMenu {
            Button("Set as Desktop") { perform(onUseDesktop) }
                .disabled(isCurrentDesktop || isBusy)
            Button("Set as Lock Screen") { perform(onUseLock) }
                .disabled(isCurrentLock || isBusy)
        }
        .task(id: item.id) {
            loadThumbnail()
        }
    }

    private var thumbnail: some View {
        ZStack {
            Design.well

            GeometryReader { geo in
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }

            if isBusy {
                busyOverlay
            } else {
                if hovering {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    HStack(spacing: 6) {
                        actionButton("Desktop", symbol: "menubar.dock.rectangle", applied: isCurrentDesktop, action: onUseDesktop)
                        actionButton("Lock Screen", symbol: "lock", applied: isCurrentLock, action: onUseLock)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(8)
                    .transition(.opacity)
                }

                if isActive && !hovering {
                    appliedBadges
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(7)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                isActive ? Color.accentColor : (hovering ? Design.hairlineStrong : Design.hairline),
                lineWidth: isActive ? 2 : 1
            )
        )
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 10 : 4, y: hovering ? 4 : 2)
        .contentShape(shape)
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 8) {
                if let fraction = downloadFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(maxWidth: 110)
                    Text("Downloading \(Int(fraction * 100))%")
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Applying…")
                }
            }
            .font(Design.font(11, weight: .medium))
            .foregroundStyle(.white)
        }
    }

    private var appliedBadges: some View {
        HStack(spacing: 4) {
            if isCurrentDesktop { badge("Desktop") }
            if isCurrentLock { badge("Lock Screen") }
        }
    }

    private func badge(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(Design.font(10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    @ViewBuilder
    private func actionButton(_ title: String, symbol: String, applied: Bool, action: @escaping () async -> Void) -> some View {
        if applied {
            OverlayButton(title: title, symbol: "checkmark") {}
                .disabled(true)
                .opacity(0.75)
        } else {
            OverlayButton(title: title, symbol: symbol) { perform(action) }
        }
    }

    private func loadThumbnail() {
        guard let url = item.thumbnailURL else { return }
        WallpaperImageStore.load(url, maxPixelSize: 480) { image in
            withAnimation(.easeOut(duration: 0.15)) {
                self.thumbnailImage = image
            }
        }
    }

    private func perform(_ action: @escaping () async -> Void) {
        guard !isBusy else { return }
        applying = true
        Task {
            await action()
            applying = false
        }
    }
}
