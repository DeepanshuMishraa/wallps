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
            case .dynamicAndStatic: return "DYNAMIC & STILLS"
            }
        }

        func matches(_ item: SystemWallpaperItem) -> Bool {
            switch self {
            case .aerials: return item.kind == .aerial
            case .dynamicAndStatic: return item.kind != .aerial
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Design.hairline).frame(height: 1)
            grid
        }
        .background(Design.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 580, minHeight: 500)
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
                StatusDot(filled: true, isGlowing: true)
                Text("SYSTEM WALLPAPERS")
                    .font(Design.mono(11, .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Design.ink)
                Spacer()
                GhostIconButton(symbol: "xmark", help: "Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.inkTertiary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Design.mono(11, .regular))
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
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Design.hairline, lineWidth: 1)
                )
                .frame(maxWidth: 250)

                Spacer(minLength: 0)

                SegmentedSwitch(options: Filter.allCases, selection: $filter) { $0.title }

                if filter == .aerials {
                    SegmentedSwitch(options: AerialMode.allCases, selection: $aerialMode) { $0.title }
                        .help("Apply aerials as looping video or a still frame")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
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
            .padding(20)
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
        VStack(spacing: 7) {
            thumbnail
            HStack(spacing: 6) {
                Text(item.name)
                    .font(Design.mono(10.5, .medium))
                    .foregroundStyle(hovering ? Design.ink : Design.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                StatusDot(filled: item.isDownloaded)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
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

            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)

            if isBusy {
                VStack(spacing: 6) {
                    if let fraction = downloadFraction {
                        Text("DOWNLOADING \(Int(fraction * 100))%")
                            .font(Design.mono(9, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(maxWidth: 90)
                    } else {
                        Text("APPLYING…")
                            .font(Design.mono(9, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    chip(symbol: "macbook", label: desktopChipLabel) { perform(onUseDesktop) }
                    chip(symbol: "lock.display", label: "LOCK") { perform(onUseLock) }
                }
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.94)

                VStack {
                    HStack {
                        if item.kind == .aerial {
                            Label("LIVE", systemImage: "play.fill")
                                .font(Design.mono(8, .bold))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                        Spacer()
                        if !item.isDownloaded {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(7)
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
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isCurrentDesktop ? Color.white.opacity(0.8) : Design.hairline,
                    lineWidth: isCurrentDesktop ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
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
            Label(label, systemImage: symbol)
                .font(Design.mono(9, .semibold))
                .tracking(0.8)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.65), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
