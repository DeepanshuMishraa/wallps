import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var attachAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit answers a quit Apple Event (sent at logout/restart/shutdown)
        // with "-128 User cancelled" while a sheet such as the catalog is
        // open, which blocked logout. Dismiss sheets and quit instead.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitEvent(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        MenuBarManager.shared.install()
        DockIconManager.apply()
        WallpaperSwitcher.shared.reapplyAtLaunchIfNeeded()
        attachWindowDelegate()
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event == nil || event?.eventID != AEEventID(kAEOpenApplication) {
            MenuBarManager.shared.hideMainWindowQuietly()
        }
    }

    @objc private func handleQuitEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        // terminate(_:) is refused while a SwiftUI sheet (catalog, file
        // picker) is up, and force-ending SwiftUI sheets corrupts its state.
        // Run the normal quit cleanup and exit directly instead.
        guard NSApp.windows.contains(where: { $0.attachedSheet != nil }) else {
            NSApp.terminate(nil)
            return
        }
        WallpaperSwitcher.shared.restoreDesktopImage()
        exit(0)
    }

    /// The main window hides instead of closing (`windowShouldClose` returns
    /// false). Without this, AppKit treats that as a veto during termination,
    /// so Wallps blocked logout, restart and shutdown ("-128 User cancelled").
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MenuBarManager.shared.windowDelegate.isTerminating = true
        return .terminateNow
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Apply Wallpapers") {
                    NotificationCenter.default.post(name: .setWallpapers, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let setWallpapers = Notification.Name("WallpsSetWallpapers")
    static let swapWallpapers = Notification.Name("WallpsSwapWallpapers")
    static let openWallpaperBrowser = Notification.Name("WallpsOpenWallpaperBrowser")
    static let refreshWallpaperPreviews = Notification.Name("WallpsRefreshPreviews")
    static let openMainWindow = Notification.Name("WallpsOpenMainWindow")
    static let wallpsStateChanged = Notification.Name("WallpsStateChanged")
}
