import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var attachAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarManager.shared.install()
        attachWindowDelegate()
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event == nil || event?.eventID != AEEventID(kAEOpenApplication) {
            MenuBarManager.shared.hideMainWindowQuietly()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WallpaperSwitcher.shared.restoreDesktopImage()
    }

    private func attachWindowDelegate() {
        guard attachAttempts < 15 else { return }
        attachAttempts += 1
        MenuBarManager.shared.attachToMainWindowIfNeeded()
        guard MenuBarManager.shared.mainWindow == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.attachWindowDelegate()
        }
    }
}

@main
struct WallpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Set wallpapers") {
                    NotificationCenter.default.post(name: .setWallpapers, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let setWallpapers = Notification.Name("WallpsSetWallpapers")
    static let refreshWallpaperPreviews = Notification.Name("WallpsRefreshPreviews")
    static let openMainWindow = Notification.Name("WallpsOpenMainWindow")
    static let wallpsStateChanged = Notification.Name("WallpsStateChanged")
}