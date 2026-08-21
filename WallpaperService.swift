import AppKit
import Foundation

enum WallpaperService {
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static func apply(desktop: URL, login: URL, legacyInstall: Bool = true) async throws -> String {
        try setDesktopWallpapers(desktop)

        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major < 26 && legacyInstall {
            try installLegacyLoginImage(login)
            return "Wallpapers set. Log out or restart to see the login screen."
        }
        return "Done. Lock your screen (⌃⌘Q) — the lock screen now shows your login image while Wallps is running."
    }

    static func currentLoginImageURL() -> URL? {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major >= 26 {
            if let saved = WallpaperSwitcher.shared.savedLoginURL,
               FileManager.default.fileExists(atPath: saved.path) {
                return saved
            }
            return nil
        }
        if let uuid = currentUserUUID() {
            let url = URL(fileURLWithPath: "/Library/Caches/Desktop Pictures/\(uuid)/lockscreen.png")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let admin = URL(fileURLWithPath: "/Library/Caches/com.apple.desktop.admin.png")
        if FileManager.default.fileExists(atPath: admin.path) {
            return admin
        }
        return nil
    }

    private static func currentUserUUID() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "GeneratedUID"]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.readToEnd(),
              let line = String(data: data, encoding: .utf8) else {
            return nil
        }
        let components = line.split(whereSeparator: \.isWhitespace)
        guard let raw = components.last, UUID(uuidString: String(raw)) != nil else {
            return nil
        }
        return String(raw)
    }

    private static func setDesktopWallpapers(_ url: URL) throws {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            try workspace.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    private static func installLegacyLoginImage(_ login: URL) throws {
        guard let png = makePNGCopy(of: login) else { return }
        defer { try? FileManager.default.removeItem(at: png) }

        let username = shellQuote(NSUserName())
        let sourcePath = shellQuote(png.path)
        let adminPath = shellQuote("/Library/Caches/com.apple.desktop.admin.png")

        let shell = "UUID=$(dscl . -read /Users/\(username) GeneratedUID | awk '{print $2}'); "
            + "D='/Library/Caches/Desktop Pictures/'$UUID; "
            + "mkdir -p '$D'; "
            + "rm -f '$D'/'lockscreen.png'; "
            + "cp \(sourcePath) '$D'/'lockscreen.png'; "
            + "chmod 644 '$D'/'lockscreen.png'; "
            + "cp \(sourcePath) \(adminPath); "
            + "chmod 644 \(adminPath)"
        try runOSAScript("do shell script \"\(shell)\" with administrator privileges")
    }

    private static func runOSAScript(_ source: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = (try? errorPipe.fileHandleForReading.readToEnd())
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw WallpaperError.loginUpdateFailed(detail: detail)
        }
    }

    private static func makePNGCopy(of source: URL) -> URL? {
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallps-login-\(UUID().uuidString).png")
        do {
            try png.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum WallpaperError: LocalizedError {
    case loginUpdateFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .loginUpdateFailed(let detail):
            if detail.localizedCaseInsensitiveContains("-128") || detail.localizedCaseInsensitiveContains("cancel") {
                return "The administrator authorization was canceled, so the legacy login image was not changed."
            }
            return "macOS did not update the legacy login image. \(detail)"
        }
    }
}