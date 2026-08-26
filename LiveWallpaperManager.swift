import AppKit
import AVFoundation
import Foundation

/// Registers videos as native macOS aerials and activates them as the live
/// lock-screen (and desktop) wallpaper. Only supported on macOS 26+, where the
/// wallpaper catalog lives under the user's Application Support folder and is
/// writable without admin privileges.
///
/// macOS offers no public API for video wallpapers — the lock screen is drawn
/// by `loginwindow`, which hosts no third-party code. The reliable path (used by
/// several open-source tools) is:
///  1. copy/transcode the video into `~/Library/Application Support/
///     com.apple.wallpaper/aerials/videos/<UUID>.mov`
///  2. generate a thumbnail and register the asset in `manifest/entries.json`
///  3. rewrite `Store/Index.plist` to make that aerial the active wallpaper
///  4. restart the wallpaper services so they pick the change up.
final class LiveWallpaperManager {
    static let shared = LiveWallpaperManager()

    private let fileManager = FileManager.default

    private var aerialsBase: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials", isDirectory: true)
    }

    private var videosDir: URL {
        aerialsBase.appendingPathComponent("videos", isDirectory: true)
    }

    private var thumbnailsDir: URL {
        aerialsBase.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private var manifestURL: URL {
        aerialsBase.appendingPathComponent("manifest/entries.json")
    }

    private var storeURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    private let categoryID = "WA000000-0000-4000-8000-000000000001"
    private let subcategoryID = "WA000000-0000-4000-8000-000000000002"

    private init() {}

    /// macOS 26 (Tahoe) hoisted the aerials catalog into the user's Application
    /// Support folder; earlier versions keep it in /Library (admin-only).
    static var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    /// Registers `videoURL` as a system aerial and activates it as the active
    /// wallpaper. Returns the activated aerial video URL (the one macOS plays).
    @discardableResult
    func setLiveLockScreen(videoURL: URL, name: String? = nil) async throws -> URL {
        guard Self.isSupported else {
            throw LiveWallpaperError.requiresTahoe
        }
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw LiveWallpaperError.fileMissing
        }
        try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        // Already living in the system aerials folder → nothing to register.
        if let existing = systemAerialURL(at: videoURL) {
            let assetID = existing.deletingPathExtension().lastPathComponent
            try activateAerial(assetID: assetID)
            return existing
        }

        // Apple's own aerials already carry temporal sub-layers and a manifest
        // entry; they only need to land in the videos folder, then activate.
        if isAppleAerial(videoURL) {
            let assetID = aerialAssetID(for: videoURL)
            let destination = videosDir.appendingPathComponent("\(assetID).mov")
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: videoURL, to: destination)
            }
            try activateAerial(assetID: assetID)
            return destination
        }

        // User video: register a fresh asset identity; transcode so the lock
        // screen keeps animating across lock/unlock cycles.
        let assetID = UUID().uuidString.uppercased()
        let destination = videosDir.appendingPathComponent("\(assetID).mov")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try await Task.detached(priority: .userInitiated) {
            try TemporalTranscoder.transcode(input: videoURL, output: destination)
        }.value

        let thumbnailURL = thumbnailsDir.appendingPathComponent("\(assetID).png")
        if !fileManager.fileExists(atPath: thumbnailURL.path) {
            generateThumbnail(from: destination, to: thumbnailURL)
        }

        insertIntoManifest(assetID: assetID, videoURL: destination, thumbnailURL: thumbnailURL, name: name)
        try activateAerial(assetID: assetID)
        return destination
    }

    /// Re-asserts an already-registered live lock screen (e.g. after a reboot).
    func reactivateAerial(for url: URL) async throws {
        guard Self.isSupported else { return }
        guard let existing = systemAerialURL(at: url) else { return }
        let assetID = existing.deletingPathExtension().lastPathComponent
        guard UUID(uuidString: assetID) != nil else { return }
        try activateAerial(assetID: assetID)
    }

    /// Activates an aerials asset as the active wallpaper by rewriting the
    /// wallpaper store and restarting the wallpaper services.
    func activateAerial(assetID: String) throws {
        writeStoreActivation(assetID: assetID)
        restartWallpaperServices()
    }

    // MARK: - Catalog helpers

    /// The system aerial URL if `url` is already inside the system aerials
    /// videos folder (macOS plays the file referenced by that identity).
    private func systemAerialURL(at url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let videoDir = videosDir.standardizedFileURL.path
        guard standardized.path.hasPrefix(videoDir) else { return nil }
        return standardized
    }

    /// Preserves Apple's asset identity when one is known; user clips get a
    /// fresh UUID so they never collide with the stock catalog.
    private func aerialAssetID(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        if UUID(uuidString: base) != nil {
            return base.uppercased()
        }
        return UUID().uuidString.uppercased()
    }

    private func isAppleAerial(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let prefixes = [
            videosDir.standardizedFileURL.path,
            SystemWallpaperCatalog.appleAerialVideosDirectory.standardizedFileURL.path,
            SystemWallpaperCatalog.aerialsDirectory.standardizedFileURL.path,
            "/Library/Application Support/com.apple.idleassetsd"
        ]
        return prefixes.contains { path.hasPrefix($0) }
    }

    // MARK: - manifest/entries.json

    private func insertIntoManifest(
        assetID: String,
        videoURL: URL,
        thumbnailURL: URL,
        name: String?
    ) {
        let displayName = name ?? videoURL.deletingPathExtension().lastPathComponent
        var entries: [String: Any]
        if let data = try? Data(contentsOf: manifestURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            entries = parsed
        } else {
            entries = ["version": 1, "categories": [] as [Any], "assets": [] as [Any]]
        }

        var categories = entries["categories"] as? [[String: Any]] ?? []
        var assets = entries["assets"] as? [[String: Any]] ?? []

        let thumbnailString = thumbnailURL.absoluteString
        let videoString = videoURL.absoluteString

        let categoryEntry: [String: Any] = [
            "id": categoryID,
            "localizedNameKey": "Wallps",
            "localizedDescriptionKey": "Wallps custom wallpaper",
            "preferredOrder": 999,
            "representativeAssetID": assetID,
            "previewImage": thumbnailString,
            "subcategories": [[
                "id": subcategoryID,
                "localizedNameKey": "Wallps",
                "localizedDescriptionKey": "Wallps custom wallpaper",
                "preferredOrder": 0,
                "previewImage": thumbnailString,
                "representativeAssetID": assetID
            ]]
        ]

        if let index = categories.firstIndex(where: { ($0["id"] as? String) == categoryID }) {
            categories[index] = categoryEntry
        } else {
            categories.append(categoryEntry)
        }

        let assetEntry: [String: Any] = [
            "id": assetID,
            "localizedNameKey": displayName,
            "accessibilityLabel": displayName,
            "shotID": "WALLPS_CUSTOM",
            "showInTopLevel": true,
            "includeInShuffle": true,
            "preferredOrder": 0,
            "categories": [categoryID],
            "subcategories": [subcategoryID],
            "url-4K-SDR-240FPS": videoString,
            "previewImage": thumbnailString,
            "pointsOfInterest": ["0": "WALLPS_0"]
        ]

        assets.removeAll { asset in
            guard let assetCategories = asset["categories"] as? [String] else { return false }
            return assetCategories.contains(categoryID)
        }
        assets.append(assetEntry)

        entries["categories"] = categories
        entries["assets"] = assets

        guard let data = try? JSONSerialization.data(
            withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        writeAtomically(data, to: manifestURL)
    }

    // MARK: - Store/Index.plist

    private func writeStoreActivation(assetID: String) {
        guard let configData = try? PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0
        ) else { return }

        var store: [String: Any]
        if let data = try? Data(contentsOf: storeURL),
           let parsed = try? PropertyListSerialization.propertyList(
               from: data, options: .mutableContainersAndLeaves, format: nil
           ) as? [String: Any] {
            store = parsed
        } else {
            store = [:]
        }

        let choice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Files": [] as [Any],
            "Configuration": configData
        ]
        let content: [String: Any] = ["Choices": [choice]]
        let entry: [String: Any] = [
            "Type": "linked",
            "Linked": [
                "Content": content,
                "LastSet": Date(),
                "LastUse": Date()
            ]
        ]

        // The global override is what makes the aerial appear on the lock
        // screen for every display; individual displays are also pointed at it.
        store["SystemDefault"] = entry
        store["AllSpacesAndDisplays"] = entry

        if var displays = store["Displays"] as? [String: Any] {
            for key in displays.keys {
                displays[key] = entry
            }
            store["Displays"] = displays
        }

        if var spaces = store["Spaces"] as? [String: Any] {
            for spaceKey in spaces.keys {
                if var space = spaces[spaceKey] as? [String: Any] {
                    if space["Default"] != nil { space["Default"] = entry }
                    if var spaceDisplays = space["Displays"] as? [String: Any] {
                        for displayKey in spaceDisplays.keys {
                            spaceDisplays[displayKey] = entry
                        }
                        space["Displays"] = spaceDisplays
                    }
                    spaces[spaceKey] = space
                }
            }
            store["Spaces"] = spaces
        }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: store, format: .binary, options: 0
        ) else { return }
        writeAtomically(data, to: storeURL)
    }

    // MARK: - Wallpaper service refresh

    private func restartWallpaperServices() {
        let cacheDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.aerials")
        if let items = try? fileManager.contentsOfDirectory(atPath: cacheDir.path) {
            for item in items where item.hasSuffix(".bmp") {
                try? fileManager.removeItem(at: cacheDir.appendingPathComponent(item))
            }
            let cacheVersion = cacheDir.appendingPathComponent("cacheVersion.db")
            try? "{\"version\":0}".data(using: .utf8)?.write(to: cacheVersion, options: .atomic)
        }
        for process in [
            "Wallpaper",
            "WallpaperAgent",
            "WallpaperAerialsExtension",
            "WallpaperImageExtension",
            "WallpaperLegacyExtension"
        ] {
            try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: [process])
        }
    }

    // MARK: - Thumbnail

    private func generateThumbnail(from videoURL: URL, to outputURL: URL) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? png.write(to: outputURL, options: .atomic)
    }

    private func writeAtomically(_ data: Data, to url: URL) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let temporary = url.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } catch {
            NSLog("Wallps: failed to write \(url.path): \(error)")
        }
    }
}

enum LiveWallpaperError: LocalizedError {
    case requiresTahoe
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .requiresTahoe:
            return "Live lock-screen wallpapers require macOS 26 (Tahoe). On earlier macOS versions, the wallpaper catalog lives in a system (admin-only) folder."
        case .fileMissing:
            return "The selected video could not be found on disk."
        }
    }
}
