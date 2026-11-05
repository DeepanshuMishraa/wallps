import AVFoundation
import AppKit
import Foundation

enum DesktopSource: Equatable {
    case image(URL)
    case video(URL)

    var url: URL {
        switch self {
        case .image(let url): return url
        case .video(let url): return url
        }
    }

    var kindString: String {
        switch self {
        case .image: return "image"
        case .video: return "video"
        }
    }

    static func from(kindString: String, path: String) -> DesktopSource? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        switch kindString {
        case "video": return .video(url)
        case "image": return .image(url)
        default: return nil
        }
    }

    static func infer(for url: URL) -> DesktopSource {
        if url.isVideoFile {
            return .video(url)
        }
        return .image(url)
    }
}

/// What feeds the lock screen. Images are held as the system wallpaper
/// (static); videos are registered as system aerials so macOS plays them
/// natively on the lock screen.
enum LoginSource: Equatable {
    case image(URL)
    case video(URL)

    var url: URL {
        switch self {
        case .image(let url): return url
        case .video(let url): return url
        }
    }

    var kindString: String {
        switch self {
        case .image: return "image"
        case .video: return "video"
        }
    }

    static func from(kindString: String, path: String) -> LoginSource? {
        let url = URL(fileURLWithPath: path)
        switch kindString {
        // A live lock video is kept even if missing: macOS updates wipe the
        // aerials folder, and launch re-registers it from its source.
        case "video": return .video(url)
        case "image" where !FileManager.default.fileExists(atPath: url.path): return nil
        case "image": return .image(url)
        default: return nil
        }
    }

    static func infer(for url: URL) -> LoginSource {
        if url.isVideoFile {
            return .video(url)
        }
        return .image(url)
    }
}

extension URL {
    var isVideoFile: Bool {
        ["mov", "mp4", "m4v"].contains(pathExtension.lowercased())
    }
}

struct SystemWallpaperItem: Identifiable {
    enum Kind: String {
        case aerial
        case dynamic
        case staticImage

        var title: String {
            switch self {
            case .aerial: return "Aerial"
            case .dynamic: return "Dynamic"
            case .staticImage: return "Still"
            }
        }
    }

    struct DownloadInfo {
        let remoteURL: URL
        let isZip: Bool
        let expectedSize: Int64?
    }

    let id: String
    let name: String
    let kind: Kind
    let collection: WallpaperCollection
    let thumbnailURL: URL?
    let localContentURL: URL?
    let download: DownloadInfo?

    var isDownloaded: Bool { localContentURL != nil }
}

/// Browser tab a wallpaper belongs to: the macOS release that introduced it,
/// or a theme for wallpapers that aren't tied to one release. Case order is
/// tab order (newest release first).
enum WallpaperCollection: String, CaseIterable, Identifiable {
    case macOS27, macOS26, macOS15, macOS14, macOS13, macOS12, bigSur, catalina, mojave
    case landscapes, cities, underwater, space, macColors, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOS27: return "macOS 27"
        case .macOS26: return "Tahoe 26"
        case .macOS15: return "Sequoia 15"
        case .macOS14: return "Sonoma 14"
        case .macOS13: return "Ventura 13"
        case .macOS12: return "Monterey 12"
        case .bigSur: return "Big Sur 11"
        case .catalina: return "Catalina"
        case .mojave: return "Mojave"
        case .landscapes: return "Landscapes"
        case .cities: return "Cities"
        case .underwater: return "Underwater"
        case .space: return "Space"
        case .macColors: return "Mac Colors"
        case .more: return "More"
        }
    }

    /// The collection for the macOS release currently running, if it has one.
    static var currentRelease: WallpaperCollection? {
        switch ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
        case 27: return .macOS27
        case 26: return .macOS26
        case 15: return .macOS15
        case 14: return .macOS14
        case 13: return .macOS13
        case 12: return .macOS12
        case 11: return .bigSur
        default: return nil
        }
    }

    /// Aerials: Apple's subcategory key names the release for the
    /// release-themed shots; the rest follow their top-level category.
    static func forAerial(subcategoryKey: String?, categoryKey: String?) -> WallpaperCollection {
        let sub = subcategoryKey ?? ""
        if sub.contains("GoldenGate") { return .macOS27 }
        if sub.contains("Tahoe") { return .macOS26 }
        if sub.contains("Sequoia") { return .macOS15 }
        if sub.contains("Sonoma") { return .macOS14 }
        switch categoryKey {
        case "AerialCategoryLandscapes": return .landscapes
        case "AerialCategoryCities": return .cities
        case "AerialCategoryUnderwater": return .underwater
        case "AerialCategorySpace": return .space
        case "AerialCategoryMac": return .macColors
        default: return .more
        }
    }

    /// Desktop pictures: release wallpapers are named after the release.
    static func forPicture(named name: String) -> WallpaperCollection {
        let lower = name.lowercased()
        let prefixes: [(String, WallpaperCollection)] = [
            ("sequoia", .macOS15), ("sonoma", .macOS14), ("ventura", .macOS13),
            ("monterey", .macOS12), ("big sur", .bigSur), ("catalina", .catalina), ("mojave", .mojave),
            ("mac ", .macColors), ("imac ", .macColors), ("hello", .macColors)
        ]
        return prefixes.first { lower.hasPrefix($0.0) }?.1 ?? .more
    }
}

enum SystemWallpaperCatalog {
    static let appSupportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("Wallps", isDirectory: true)

    static var aerialsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Aerials", isDirectory: true)
    }

    static var dynamicDirectory: URL {
        appSupportDirectory.appendingPathComponent("Dynamic", isDirectory: true)
    }

    static var postersDirectory: URL {
        appSupportDirectory.appendingPathComponent("Posters", isDirectory: true)
    }

    static var dropsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Drops", isDirectory: true)
    }

    private static let desktopPicturesDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
    private static let systemWallpapersDirectory = URL(fileURLWithPath: "/System/Library/Wallpapers")
    /// macOS 13–25 shipped the aerial manifest inside this framework.
    private static let legacyAerialResourcesDirectory = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/WallpaperAerialAssets.framework/Resources")
    static let appleAerialsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials", isDirectory: true)
    static let appleAerialVideosDirectory = appleAerialsDirectory.appendingPathComponent("videos", isDirectory: true)
    /// Category Wallps registers custom live lock screens under; never listed as an Apple wallpaper.
    static let wallpsAerialCategoryID = "WA000000-0000-4000-8000-000000000001"

    /// Where the aerial manifest (`entries.json`) and its string tables live.
    /// macOS 26+ downloads them into the user's wallpaper folder; older
    /// releases bundle them in the WallpaperAerialAssets framework.
    private static var aerialManifestDirectory: URL? {
        [appleAerialsDirectory.appendingPathComponent("manifest", isDirectory: true), legacyAerialResourcesDirectory]
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("entries.json").path) }
    }

    private static func aerialThumbnail(id: String) -> URL? {
        [
            appleAerialsDirectory.appendingPathComponent("thumbnails/\(id).png"),
            legacyAerialResourcesDirectory.appendingPathComponent("\(id).png")
        ].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static var inMemoryCatalog: [SystemWallpaperItem]?
    private static let catalogLock = NSLock()

    static func makeDirectories() {
        for directory in [appSupportDirectory, aerialsDirectory, dynamicDirectory, postersDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func items(forceRefresh: Bool = false) -> [SystemWallpaperItem] {
        catalogLock.lock()
        if !forceRefresh, let cached = inMemoryCatalog {
            catalogLock.unlock()
            return cached
        }
        catalogLock.unlock()

        var result: [SystemWallpaperItem] = []
        result.append(contentsOf: aerialItems())
        // A wallpaper shipped as a local still (e.g. Sonoma.heic) needs no
        // download, so drop its downloadable dynamic twin.
        let stills = staticImageItems()
        let stillNames = Set(stills.map { $0.name.lowercased() })
        result.append(contentsOf: dynamicItems().filter { !stillNames.contains($0.name.lowercased()) })
        result.append(contentsOf: stills)

        catalogLock.lock()
        inMemoryCatalog = result
        catalogLock.unlock()

        return result
    }

    static func invalidateCatalogCache() {
        catalogLock.lock()
        inMemoryCatalog = nil
        catalogLock.unlock()
    }

    static func localizedAerialNames() -> [String: String] {
        guard let manifest = aerialManifestDirectory else { return [:] }
        let bundle = manifest.appendingPathComponent("TVIdleScreenStrings.bundle")
        let loctable = [
            bundle.appendingPathComponent("Contents/Resources/Localizable.nocache.loctable"),
            bundle.appendingPathComponent("Localizable.nocache.loctable")
        ].first { FileManager.default.fileExists(atPath: $0.path) }
        guard let loctable,
              let data = try? Data(contentsOf: loctable),
              let root = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any] else {
            return [:]
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let base = String(preferred.split(separator: "-").first ?? Substring("en"))
        let candidates = [preferred.replacingOccurrences(of: "-", with: "_"), base, "en"]
        for candidate in candidates {
            guard let table = dictionaryTable(from: root[candidate]) else { continue }
            return table.compactMapValues { $0 as? String }
        }
        let firstKey = root.keys.sorted().first
        guard let firstKey, let table = dictionaryTable(from: root[firstKey]) else { return [:] }
        return table.compactMapValues { $0 as? String }
    }

    private static func dictionaryTable(from value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let data = value as? Data,
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
              as? [String: Any] {
            return dict
        }
        return nil
    }

    private static func aerialItems() -> [SystemWallpaperItem] {
        guard let manifest = aerialManifestDirectory,
              let data = try? Data(contentsOf: manifest.appendingPathComponent("entries.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else {
            return []
        }
        makeDirectories()
        let names = localizedAerialNames()
        let systemVideoIDs = Set((try? FileManager.default.contentsOfDirectory(
            atPath: appleAerialVideosDirectory.path
        ).map { ($0 as NSString).deletingPathExtension }) ?? [])

        // Category + subcategory names, and category order (newest macOS
        // wallpapers come first in Apple's manifest).
        let categories = root["categories"] as? [[String: Any]] ?? []
        var categoryOrder: [String: Int] = [:]
        var categoryKeys: [String: String] = [:]
        var subcategoryKeys: [String: String] = [:]
        for (index, category) in categories.enumerated() {
            guard let categoryID = category["id"] as? String else { continue }
            categoryOrder[categoryID] = (category["preferredOrder"] as? Int) ?? index
            categoryKeys[categoryID] = category["localizedNameKey"] as? String
            for sub in category["subcategories"] as? [[String: Any]] ?? [] {
                if let subID = sub["id"] as? String, let key = sub["localizedNameKey"] as? String {
                    subcategoryKeys[subID] = key
                }
            }
        }

        let ordered = assets.enumerated().sorted { lhs, rhs in
            let left = (lhs.element["categories"] as? [String])?.first.flatMap { categoryOrder[$0] } ?? Int.max
            let right = (rhs.element["categories"] as? [String])?.first.flatMap { categoryOrder[$0] } ?? Int.max
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)

        return ordered.compactMap { asset -> SystemWallpaperItem? in
            guard let id = asset["id"] as? String,
                  let remote = asset["url-4K-SDR-240FPS"] as? String,
                  let remoteURL = URL(string: remote),
                  remoteURL.scheme == "https",
                  !((asset["categories"] as? [String])?.contains(wallpsAerialCategoryID) ?? false) else {
                return nil
            }
            let nameKey = asset["localizedNameKey"] as? String
            let fallbackName = (asset["shotID"] as? String)?
                .replacingOccurrences(of: "_", with: " ")
                .titleCasedWords() ?? id
            var name = nameKey.flatMap { names[$0] } ?? fallbackName
            let subcategoryKey = (asset["subcategories"] as? [String])?.first.flatMap { subcategoryKeys[$0] }
            let collection = WallpaperCollection.forAerial(
                subcategoryKey: subcategoryKey,
                categoryKey: (asset["categories"] as? [String])?.first.flatMap { categoryKeys[$0] }
            )
            // Appearance/orientation variants (e.g. macOS 27's Golden Gate
            // "Light"/"Dark") only carry the variant name; prefix the family.
            if let variant = asset["variant"] as? [String: Any] {
                if let family = subcategoryKey.flatMap({ names[$0] }),
                   !name.localizedCaseInsensitiveContains(family) {
                    name = "\(family) \(name)"
                }
                if (variant["orientation"] as? String) == "portrait" {
                    name += " (Portrait)"
                }
            }

            let thumbnail = aerialThumbnail(id: id)
            let ours = aerialsDirectory.appendingPathComponent("\(id).mov")
            let local: URL?
            if FileManager.default.fileExists(atPath: ours.path) {
                local = ours
            } else if systemVideoIDs.contains(id) {
                local = appleAerialVideosDirectory.appendingPathComponent("\(id).mov")
            } else {
                local = nil
            }

            return SystemWallpaperItem(
                id: id,
                name: name,
                kind: .aerial,
                collection: collection,
                thumbnailURL: thumbnail,
                localContentURL: local,
                download: SystemWallpaperItem.DownloadInfo(
                    remoteURL: remoteURL, isZip: false, expectedSize: nil
                )
            )
        }
    }

    private static func dynamicItems() -> [SystemWallpaperItem] {
        let descriptors = (try? FileManager.default.contentsOfDirectory(
            at: desktopPicturesDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "madesktop" }) ?? []

        let catalog = mobileAssetCatalogByID()
        let names = localizedAerialNames()

        // assetID → thumbnail. Descriptors on disk win; downloadable assets
        // without a descriptor (macOS 27 drops several, e.g. Tree, Valley,
        // Ventura Graphic) still have a thumbnail in `.thumbnails`.
        var thumbnails: [String: URL] = [:]
        for descriptor in descriptors {
            guard let plist = NSDictionary(contentsOf: descriptor),
                  let assetID = plist["mobileAssetID"] as? String else { continue }
            thumbnails[assetID] = (plist["thumbnailPath"] as? String).map { URL(fileURLWithPath: $0) }
                ?? stillThumbnail(named: assetID)
        }
        for assetID in catalog.keys where thumbnails[assetID] == nil {
            thumbnails[assetID] = stillThumbnail(named: assetID)
        }
        let assetIDs = orderedByAppleListing(Array(thumbnails.keys))

        return assetIDs.compactMap { assetID in
            let name = names[assetID] ?? assetID
            let thumbnail = thumbnails[assetID]
            let installed = dynamicDirectory
                .appendingPathComponent(sanitized(name))
                .appendingPathComponent("content.heic")

            let downloadInfo: SystemWallpaperItem.DownloadInfo?
            if let entry = catalog[assetID], !FileManager.default.fileExists(atPath: installed.path) {
                downloadInfo = SystemWallpaperItem.DownloadInfo(
                    remoteURL: entry.remoteURL,
                    isZip: true,
                    expectedSize: entry.size
                )
            } else {
                downloadInfo = nil
            }
            let isInstalled = FileManager.default.fileExists(atPath: installed.path)
            guard isInstalled || downloadInfo != nil else { return nil }

            return SystemWallpaperItem(
                id: "dynamic-\(assetID)",
                name: name,
                kind: .dynamic,
                collection: WallpaperCollection.forPicture(named: name),
                thumbnailURL: thumbnail.flatMap { FileManager.default.fileExists(atPath: $0.path) } == true
                    ? thumbnail : nil,
                localContentURL: isInstalled ? installed : nil,
                download: downloadInfo
            )
        }
    }

    /// Small pre-rendered preview Apple ships for a desktop picture, if any.
    private static func stillThumbnail(named name: String) -> URL? {
        let url = desktopPicturesDirectory.appendingPathComponent(".thumbnails/\(name).heic")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Sorts names the way System Settings lists them (`.orderedPictures.plist`,
    /// newest first); anything not listed keeps a stable alphabetical tail.
    private static func orderedByAppleListing(_ names: [String]) -> [String] {
        let listing = NSArray(contentsOf: desktopPicturesDirectory.appendingPathComponent(".orderedPictures.plist"))
            as? [String] ?? []
        var rank: [String: Int] = [:]
        for (index, file) in listing.enumerated() where rank[(file as NSString).deletingPathExtension] == nil {
            rank[(file as NSString).deletingPathExtension] = index
        }
        return names.sorted { lhs, rhs in
            switch (rank[lhs], rank[rhs]) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    private struct MobileAssetEntry {
        let remoteURL: URL
        let size: Int64?
    }

    private static func mobileAssetCatalogByID() -> [String: MobileAssetEntry] {
        let xml = URL(fileURLWithPath:
            "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture/com_apple_MobileAsset_DesktopPicture.xml")
        guard let plist = NSDictionary(contentsOf: xml),
              let assets = plist["Assets"] as? [[String: Any]] else {
            return [:]
        }
        var result: [String: MobileAssetEntry] = [:]
        for asset in assets {
            guard let id = asset["DesktopPictureID"] as? String,
                  let baseURLString = asset["__BaseURL"] as? String,
                  let relativePath = asset["__RelativePath"] as? String,
                  let baseURL = URL(string: baseURLString) else {
                continue
            }
            result[id] = MobileAssetEntry(
                remoteURL: URL(string: relativePath, relativeTo: baseURL)?.absoluteURL ?? baseURL,
                size: (asset["_DownloadSize"] as? NSNumber)?.int64Value
            )
        }
        return result
    }

    private static func staticImageItems() -> [SystemWallpaperItem] {
        let fileManager = FileManager.default
        let imageExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png"]
        func images(in directory: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        }

        var byName: [String: URL] = [:]
        for url in images(in: desktopPicturesDirectory) {
            byName[url.deletingPathExtension().lastPathComponent] = url
        }
        // Hidden per-wallpaper folders (e.g. `.wallpapers/Sonoma Horizon/`).
        let hidden = desktopPicturesDirectory.appendingPathComponent(".wallpapers", isDirectory: true)
        for folder in (try? fileManager.contentsOfDirectory(at: hidden, includingPropertiesForKeys: nil)) ?? [] {
            for url in images(in: folder) where !url.lastPathComponent.localizedCaseInsensitiveContains("thumbnail") {
                byName[url.deletingPathExtension().lastPathComponent] = url
            }
        }
        // The current macOS default still (macOS 26+).
        let defaultAerial = systemWallpapersDirectory.appendingPathComponent(".default/DefaultAerial.heic")
        if fileManager.fileExists(atPath: defaultAerial.path) {
            byName["macOS Default"] = defaultAerial
        }

        return orderedByAppleListing(Array(byName.keys)).compactMap { name in
            guard let url = byName[name] else { return nil }
            return SystemWallpaperItem(
                id: "static-\(url.lastPathComponent)",
                name: name,
                kind: .staticImage,
                // The bundled default still is the running release's wallpaper.
                collection: url == defaultAerial
                    ? WallpaperCollection.currentRelease ?? .more
                    : WallpaperCollection.forPicture(named: name),
                thumbnailURL: stillThumbnail(named: name) ?? url,
                localContentURL: url,
                download: nil
            )
        }
    }

    /// Extracts a still poster frame from an aerial video, cached on disk.
    static func posterFrame(forVideoAt videoURL: URL, preferredID: String) async -> URL? {
        let cached = postersDirectory.appendingPathComponent("\(sanitized(preferredID))-poster.png")
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        makeDirectories()
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        do {
            let duration = try await asset.load(.duration)
            let midpoint = CMTime(seconds: min(2, duration.seconds * 0.2), preferredTimescale: 600)
            let (frame, _) = try await generator.image(at: midpoint)
            let rep = NSBitmapImageRep(cgImage: frame)
            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            try png.write(to: cached, options: .atomic)
            return cached
        } catch {
            return nil
        }
    }

    static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "wallpaper" : cleaned
    }
}

extension String {
    fileprivate func titleCasedWords() -> String {
        split(separator: " ").map { $0.prefix(1).capitalized + $0.dropFirst().lowercased() }.joined(separator: " ")
    }
}

@MainActor
final class WallpaperDownloadCenter: ObservableObject {
    static let shared = WallpaperDownloadCenter()

    @Published private(set) var progress: [String: Double] = [:]
    private var tasks: [String: Task<URL, Error>] = [:]

    func ensureDownloaded(_ item: SystemWallpaperItem) async throws -> URL {
        if let existing = item.localContentURL {
            return existing
        }
        guard let info = item.download else {
            throw WallpaperDownloadError.noSource(itemName: item.name)
        }
        if let running = tasks[item.id] {
            return try await running.value
        }
        let task = Task<URL, Error> { [weak self] in
            guard let self else { throw WallpaperDownloadError.cancelled }
            defer {
                self.tasks[item.id] = nil
                self.progress[item.id] = nil
                SystemWallpaperCatalog.invalidateCatalogCache()
            }
            do {
                let url = try await Self.download(info: info, item: item) { fraction in
                    Task { @MainActor in
                        self.progress[item.id] = fraction
                    }
                }
                return url
            } catch {
                await MainActor.run { self.progress[item.id] = nil }
                throw error
            }
        }
        tasks[item.id] = task
        return try await task.value
    }

    private nonisolated static func download(
        info: SystemWallpaperItem.DownloadInfo,
        item: SystemWallpaperItem,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        SystemWallpaperCatalog.makeDirectories()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallps-\(UUID().uuidString)-\(info.isZip ? "asset.zip" : "asset.mov")")

        // A download task streams straight to disk; iterating `AsyncBytes`
        // byte-by-byte made multi-GB 4K aerials take many minutes of CPU.
        let delegate = DownloadToFileDelegate(destination: temporary, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let response = try await delegate.run(session.downloadTask(with: info.remoteURL))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw WallpaperDownloadError.badResponse(itemName: item.name, statusCode: http.statusCode)
        }
        onProgress(1.0)

        if info.isZip {
            return try extractPrimaryImage(fromZipAt: temporary, item: item)
        }

        let destination = SystemWallpaperCatalog.aerialsDirectory.appendingPathComponent("\(item.id).mov")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private nonisolated static func extractPrimaryImage(fromZipAt zipURL: URL, item: SystemWallpaperItem) throws -> URL {
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallps-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, extractionDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WallpaperDownloadError.extractionFailed(itemName: item.name)
        }

        let assetData = extractionDirectory.appendingPathComponent("AssetData")
        let searchRoot = FileManager.default.fileExists(atPath: assetData.path) ? assetData : extractionDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: searchRoot, includingPropertiesForKeys: [.fileSizeKey]
        ))?.filter {
            ["heic", "heif", "jpg", "png"].contains($0.pathExtension.lowercased())
        } ?? []
        guard let primary = files.max(by: {
            ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                < ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }) else {
            throw WallpaperDownloadError.extractionFailed(itemName: item.name)
        }

        let destinationDirectory = SystemWallpaperCatalog.dynamicDirectory
            .appendingPathComponent(SystemWallpaperCatalog.sanitized(item.name), isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent("content.heic")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: primary, to: destination)
        try? FileManager.default.removeItem(at: zipURL)
        return destination
    }
}

/// Bridges a `URLSessionDownloadTask` to async/await with progress. The
/// finished file is moved to `destination` inside the delegate callback,
/// because URLSession deletes its temporary file as soon as it returns.
private final class DownloadToFileDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var moveError: Error?
    private var lastReported = -1.0

    init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(_ task: URLSessionDownloadTask) async throws -> URLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        guard fraction - lastReported >= 0.01 else { return }
        lastReported = fraction
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let error = error ?? moveError {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: response)
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }
}

enum WallpaperDownloadError: LocalizedError {
    case noSource(itemName: String)
    case cancelled
    case extractionFailed(itemName: String)
    case badResponse(itemName: String, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noSource(let itemName):
            return "\"\(itemName)\" has no downloadable source registered by macOS."
        case .cancelled:
            return "The wallpaper download was cancelled."
        case .badResponse(let itemName, let statusCode):
            return "Apple's server refused the download for \"\(itemName)\" (HTTP \(statusCode)). "
                + "Your current wallpapers were not changed. Try again later, or pick another wallpaper."
        case .extractionFailed(let itemName):
            return "The downloaded package for \"\(itemName)\" could not be unpacked. Nothing was changed."
        }
    }
}
