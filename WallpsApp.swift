import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event == nil || event?.eventID != AEEventID(kAEOpenApplication) {
            NSApp.hide(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WallpaperSwitcher.shared.restoreDesktopImage()
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
}