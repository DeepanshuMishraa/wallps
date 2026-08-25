import AppKit
import SwiftUI

struct SystemWallpaperBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadCenter = WallpaperDownloadCenter.shared
    @State private var items: [SystemWallpaperItem] = []
    @State private var filter: Filter = .aerials
    @State private var aerialMode: AerialMode = .live
    @State private var searchText = ""
    @State private var alert: WallpaperService.AlertMessage?

    enum AerialMode: String, CaseIterable, Identifiable {
        case live
        case still

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: return "LIVE"
            case .still: return "STILL"
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case aerials
        case dynamicAndStatic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aerials: return "AERIALS"
            case .dynamicAndStatic: return "SYSTEM STILLS"
            }
        }

        func matches(_ item: SystemWallpaperItem) -> Bool {
            switch self {
            case .aerials: return item.kind == .aerial
            case .dynamicAndStatic: return item.kind != .aerial
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 360), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
        }
        .background(Design.background)
        .frame(minWidth: 640, idealWidth: 840, maxWidth: .infinity, minHeight: 480, idealHeight: 600, maxHeight: .infinity)
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
    }

    private var filteredItems: [SystemWallpaperItem] {
        items
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .filter(filter.matches)
            .sorted {
                if $0.isDownloaded != $1.isDownloaded { return $0.isDownloaded }
                return $0.name < $1.name
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusDot(filled: true, isGlowing: true, customColor: Design.accent)

                Text("APPLE WALLPAPERS & 4K AERIALS")
                    .font(Design.font(12, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(Design.ink)

                Spacer()

                GhostIconButton(symbol: "xmark", text: "CLOSE", help: "Close Catalog (ESC)") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ViewThatFits(in: .horizontal) {
                // Wide layout
                HStack(spacing: 12) {
                    searchBarView
                        .frame(maxWidth: 280)

                    Spacer(minLength: 0)

                    SegmentedSwitch(options: Filter.allCases, selection: $filter) { $0.title }

                    if filter == .aerials {
                        SegmentedSwitch(options: AerialMode.allCases, selection: $aerialMode) { $0.title }
                            .help("Apply aerials as looping video or still frame")
                    }
                }

                // Narrow layout
                VStack(alignment: .leading, spacing: 10) {
                    searchBarView

                    HStack(spacing: 8) {
                        SegmentedSwitch(options: Filter.allCases, selection: $filter) { $0.title }

                        if filter == .aerials {
                            SegmentedSwitch(options: AerialMode.allCases, selection: $aerialMode) { $0.title }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Design.inkTertiary)
            TextField("SEARCH CATALOG…", text: $searchText)
                .textFieldStyle(.plain)
                .font(Design.font(11, weight: .regular))
                .foregroundStyle(Design.ink)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.inkTertiary)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: 1)
        )
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredItems) { item in
                    SystemWallpaperCellView(
                        item: item,
                        downloadFraction: downloadCenter.progress[item.id],
                        isCurrentDesktop: WallpaperSwitcher.shared.savedDesktopURL?.standardizedFileURL
                            == item.localContentURL?.standardizedFileURL,
                        desktopChipLabel: item.kind == .aerial ? "DESKTOP · \(aerialMode.title)" : "DESKTOP",
                        onUseDesktop: { await use(item, for: .desktop) },
                        onUseLock: { await use(item, for: .login) }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private func loadItemsFast() {
        Task.detached(priority: .userInitiated) {
            let loaded = SystemWallpaperCatalog.items()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.items = loaded
                }
            }
        }
    }

    private enum ApplyTarget {
        case desktop
        case login
    }

    private func use(_ item: SystemWallpaperItem, for target: ApplyTarget) async {
        do {
            let contentURL = try await downloadCenter.ensureDownloaded(item)

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
                _ = try await WallpaperSwitcher.shared.applyAndArm(desktop: nil, login: lockImageURL)
            }
            NotificationCenter.default.post(name: .wallpsStateChanged, object: nil)
        } catch {
            alert = WallpaperService.AlertMessage(
                title: "Could not use \"\(item.name)\"",
                message: error.localizedDescription
            )
        }
    }
}

private struct SystemWallpaperCellView: View {
    let item: SystemWallpaperItem
    let downloadFraction: Double?
    let isCurrentDesktop: Bool
    var desktopChipLabel: String = "DESKTOP"
    let onUseDesktop: () async -> Void
    let onUseLock: () async -> Void

    @State private var thumbnailImage: NSImage?
    @State private var hovering = false
    @State private var applying = false

    private var isBusy: Bool { downloadFraction != nil || applying }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            HStack(spacing: 6) {
                Text(item.name.uppercased())
                    .font(Design.font(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(hovering ? Design.ink : Design.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if item.isDownloaded {
                    StatusDot(filled: true, customColor: Design.success)
                }
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(item.name)\(item.isDownloaded ? "" : " — downloads on first use")")
        .task(id: item.id) {
            loadThumbnail()
        }
    }

    private var thumbnail: some View {
        ZStack {
            Rectangle()
                .fill(Design.surface)

            GeometryReader { geo in
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                } else if !isBusy {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Design.inkTertiary)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)

            if isBusy {
                VStack(spacing: 6) {
                    if let fraction = downloadFraction {
                        Text("DOWNLOADING \(Int(fraction * 100))%")
                            .font(Design.font(9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(maxWidth: 90)
                    } else {
                        Text("APPLYING…")
                            .font(Design.font(9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    chip(symbol: "macbook", label: desktopChipLabel) { perform(onUseDesktop) }
                    chip(symbol: "lock.display", label: "LOCK") { perform(onUseLock) }
                }
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.94)

                VStack {
                    HStack {
                        if item.kind == .aerial {
                            Text("[ LIVE 4K ]")
                                .font(Design.font(8, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        Spacer()
                        if !item.isDownloaded {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(4)
                                .background(Color.black.opacity(0.75), in: Circle())
                        }
                    }
                    Spacer()
                }
                .padding(6)
                .opacity(hovering ? 0 : 1)
            }

            if isCurrentDesktop && !isBusy {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black, Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                    .opacity(hovering ? 0 : 1)
            }
        }
        .aspectRatio(16/10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isCurrentDesktop ? Color.white.opacity(0.8) : (hovering ? Design.hairlineStrong : Design.hairline),
                    lineWidth: isCurrentDesktop ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func chip(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(Design.font(9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .disabled(isBusy)
    }
}
