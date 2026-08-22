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
        let videoExtensions = ["mov", "mp4", "m4v"]
        if videoExtensions.contains(url.pathExtension.lowercased()) {
            return .video(url)
        }
        return .image(url)
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
    let thumbnailURL: URL?
    let localContentURL: URL?
    let download: DownloadInfo?

    var isDownloaded: Bool { localContentURL != nil }
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

    private static let desktopPicturesDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
    private static let aerialResourcesDirectory = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/WallpaperAerialAssets.framework/Resources")
    private static let appleAerialVideosDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)

    static func makeDirectories() {
        for directory in [appSupportDirectory, aerialsDirectory, dynamicDirectory, postersDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func items() -> [SystemWallpaperItem] {
        var result: [SystemWallpaperItem] = []
        result.append(contentsOf: aerialItems())
        result.append(contentsOf: dynamicItems())
        result.append(contentsOf: staticImageItems())
        return result
    }

    static func localizedAerialNames() -> [String: String] {
        let loctable = aerialResourcesDirectory
            .appendingPathComponent("TVIdleScreenStrings.bundle/Localizable.nocache.loctable")
        guard let data = try? Data(contentsOf: loctable),
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
        let entriesURL = aerialResourcesDirectory.appendingPathComponent("entries.json")
        guard let data = try? Data(contentsOf: entriesURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else {
            return []
        }
        makeDirectories()
        let names = localizedAerialNames()
        let systemVideoIDs = Set((try? FileManager.default.contentsOfDirectory(
            atPath: appleAerialVideosDirectory.path
        ).map { ($0 as NSString).deletingPathExtension }) ?? [])

        return assets.compactMap { asset -> SystemWallpaperItem? in
            guard let id = asset["id"] as? String,
                  let remote = asset["url-4K-SDR-240FPS"] as? String,
                  let remoteURL = URL(string: remote) else {
                return nil
            }
            let nameKey = asset["localizedNameKey"] as? String
            let fallbackName = (asset["shotID"] as? String)?
                .replacingOccurrences(of: "_", with: " ")
                .titleCasedWords() ?? id
            let name = nameKey.flatMap { names[$0] } ?? fallbackName

            let thumbnail = aerialResourcesDirectory.appendingPathComponent("\(id).png")
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
                thumbnailURL: FileManager.default.fileExists(atPath: thumbnail.path) ? thumbnail : nil,
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
        guard !descriptors.isEmpty else { return [] }

        let catalog = mobileAssetCatalogByID()
        let names = localizedAerialNames()

        return descriptors.compactMap { descriptor in
            guard let plist = NSDictionary(contentsOf: descriptor),
                  let assetID = plist["mobileAssetID"] as? String else {
                return nil
            }
            let name = names[assetID] ?? descriptor.deletingPathExtension().lastPathComponent
            let thumbnailPath = plist["thumbnailPath"] as? String
            let thumbnail = thumbnailPath.map { URL(fileURLWithPath: $0) }
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

            return SystemWallpaperItem(
                id: "dynamic-\(assetID)",
                name: name,
                kind: .dynamic,
                thumbnailURL: thumbnail.flatMap { FileManager.default.fileExists(atPath: $0.path) } == true
                    ? thumbnail : nil,
                localContentURL: FileManager.default.fileExists(atPath: installed.path) ? installed : nil,
                download: downloadInfo
            )
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
        let images = (try? FileManager.default.contentsOfDirectory(
            at: desktopPicturesDirectory, includingPropertiesForKeys: nil
        ).filter { ["heic", "heif", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }) ?? []
        return images.map { url in
            SystemWallpaperItem(
                id: "static-\(url.lastPathComponent)",
                name: url.deletingPathExtension().lastPathComponent,
                kind: .staticImage,
                thumbnailURL: url,
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
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        do {
            let duration = try await asset.load(.duration)
            let midpoint = CMTime(seconds: min(3, duration.seconds * 0.25), preferredTimescale: 600)
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
            defer { self.tasks[item.id] = nil; self.progress[item.id] = nil }
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
        let session = URLSession.shared
        let (bytes, response) = try await session.bytes(from: info.remoteURL)
        let expectedLength = response.expectedContentLength

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallps-\(UUID().uuidString)-\(info.isZip ? "asset.zip" : "asset.mov")")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)

        var written: Int64 = 0
        var lastReported = -1.0
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                reportProgress(written, expectedLength, &lastReported, onProgress)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
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

    private nonisolated static func reportProgress(
        _ written: Int64,
        _ expectedLength: Int64,
        _ lastReported: inout Double,
        _ onProgress: (Double) -> Void
    ) {
        guard expectedLength > 0 else { return }
        let fraction = Double(written) / Double(expectedLength)
        if abs(fraction - lastReported) >= 0.01 {
            lastReported = fraction
            onProgress(fraction)
        }
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

enum WallpaperDownloadError: LocalizedError {
    case noSource(itemName: String)
    case cancelled
    case extractionFailed(itemName: String)

    var errorDescription: String? {
        switch self {
        case .noSource(let itemName):
            return "\"\(itemName)\" has no downloadable source registered by macOS."
        case .cancelled:
            return "The wallpaper download was cancelled."
        case .extractionFailed(let itemName):
            return "The downloaded package for \"\(itemName)\" could not be unpacked. Nothing was changed."
        }
    }
}
