import AppKit
import SwiftUI

struct SystemWallpaperBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadCenter = WallpaperDownloadCenter.shared
    @State private var items: [SystemWallpaperItem] = []
    @State private var images: [String: NSImage] = [:]
    @State private var filter: Filter = .aerials
    @State private var alert: WallpaperService.AlertMessage?

    enum Filter: String, CaseIterable, Identifiable {
        case aerials
        case dynamicAndStatic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aerials: return "Aerials"
            case .dynamicAndStatic: return "Dynamic & Stills"
            }
        }

        func matches(_ item: SystemWallpaperItem) -> Bool {
            switch self {
            case .aerials: return item.kind == .aerial
            case .dynamicAndStatic: return item.kind != .aerial
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await loadItems()
        }
    }

    private var filteredItems: [SystemWallpaperItem] {
        items.filter(filter.matches).sorted {
            if $0.isDownloaded != $1.isDownloaded { return $0.isDownloaded }
            return $0.name < $1.name
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("System wallpapers")
                    .font(.system(size: 16, weight: .bold))
                Text("Everything macOS ships — undownloaded items fetch on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $filter.animation(.easeInOut(duration: 0.2))) {
                ForEach(Filter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filteredItems) { item in
                    SystemWallpaperCellView(
                        item: item,
                        image: images[item.id],
                        downloadFraction: downloadCenter.progress[item.id],
                        isCurrentDesktop: WallpaperSwitcher.shared.savedDesktopURL?.standardizedFileURL
                            == item.localContentURL?.standardizedFileURL,
                        onUseDesktop: { await use(item, for: .desktop) },
                        onUseLock: { await use(item, for: .login) }
                    )
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Hover a wallpaper and pick Desktop or Lock. Aerials play as live videos on your desktop; the lock screen gets a still frame from them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func loadItems() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            SystemWallpaperCatalog.items()
        }.value
        withAnimation(.easeOut(duration: 0.25)) {
            items = loaded
        }
        await preloadImages(for: loaded)
    }

    private func preloadImages(for loaded: [SystemWallpaperItem]) async {
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for item in loaded.prefix(160) {
                guard let thumbnail = item.thumbnailURL else { continue }
                group.addTask {
                    let image = await Task.detached(priority: .utility) {
                        NSImage(contentsOf: thumbnail)
                    }.value
                    return (item.id, image)
                }
            }
            for await (id, image) in group {
                guard let image else { continue }
                images[id] = image
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
                let source: DesktopSource = item.kind == .aerial ? .video(contentURL) : .image(contentURL)
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
    let image: NSImage?
    let downloadFraction: Double?
    let isCurrentDesktop: Bool
    let onUseDesktop: () async -> Void
    let onUseLock: () async -> Void

    @State private var hovering = false

    private var isBusy: Bool { downloadFraction != nil || applying }

    @State private var applying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !isBusy {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

            if isBusy {
                VStack(spacing: 6) {
                    if let fraction = downloadFraction {
                        Text("Downloading… \(Int(fraction * 100))%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(.white)
                    } else {
                        Text("Applying…")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            } else {
                Text(item.isDownloaded ? item.name : "\(item.name) · not downloaded")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 8)
                    .opacity(hovering ? 0 : 1)

                HStack(spacing: 8) {
                    chip(symbol: "macbook", label: "Desktop") { perform(onUseDesktop) }
                    chip(symbol: "lock.display", label: "Lock") { perform(onUseLock) }
                }
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.94)
                .padding(.bottom, 6)
            }

            if isCurrentDesktop && !isBusy {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isCurrentDesktop ? Color.accentColor : Color.primary.opacity(0.06),
                    lineWidth: isCurrentDesktop ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .help(item.name)
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
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
