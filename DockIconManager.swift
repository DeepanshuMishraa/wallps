import AppKit

enum DockIconManager {
    private static let storageKey = "WallpsHideDockIcon"

    static var isHidden: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func setHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: storageKey)
        apply()
    }

    static func apply() {
        NSApp.setActivationPolicy(isHidden ? .accessory : .regular)
    }
}
