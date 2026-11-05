import AppKit
import CoreText
import SwiftUI

// MARK: - Font Registrar

enum FontRegistrar {
    private static var hasRegistered = false
    private static let bundledFontNames = [
        "GeistSerif-Variable",
        "Cove-Light",
        "Cove-Regular",
        "Cove-Medium",
        "Cove-SemiBold",
        "Cove-Bold"
    ]

    static func registerBundledFonts() {
        guard !hasRegistered else { return }
        hasRegistered = true

        var fontURLs: [URL] = []

        for name in bundledFontNames {
            if let bundleNested = Bundle.main.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: "Resources/Fonts"
            ) {
                fontURLs.append(bundleNested)
            }

            if let bundleRoot = Bundle.main.url(forResource: name, withExtension: "ttf") {
                fontURLs.append(bundleRoot)
            }

            let userFontsURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Fonts")
                .appendingPathComponent("\(name).ttf")
            if FileManager.default.fileExists(atPath: userFontsURL.path) {
                fontURLs.append(userFontsURL)
            }

            let systemFontsURL = URL(fileURLWithPath: "/Library/Fonts/\(name).ttf")
            if FileManager.default.fileExists(atPath: systemFontsURL.path) {
                fontURLs.append(systemFontsURL)
            }
        }

        for url in fontURLs {
            var registrationError: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
        }
    }
}

// MARK: - Dynamic Color Helper

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - Design Tokens

/// Native macOS look: SF Pro at system sizes, semantic system colors, and the
/// user's accent color. Custom values exist only where AppKit has no
/// equivalent (preview strokes, dimming over images).
enum Design {
    static let ink = Color.primary
    static let inkSecondary = Color.secondary
    static let inkTertiary = Color(nsColor: .tertiaryLabelColor)

    static let hairline = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.12)
    )

    static let hairlineStrong = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.22),
        dark: NSColor.white.withAlphaComponent(0.26)
    )

    /// Resting fill for empty wells and placeholders.
    static let well = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.04),
        dark: NSColor.white.withAlphaComponent(0.05)
    )

    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)

    static let previewRadius: CGFloat = 12

    /// Cove for all interface text. Cove draws lighter than SF Pro at the same
    /// nominal weight, so each request renders one step heavier (regular →
    /// Medium, medium → SemiBold, …). Falls back to SF Pro if registration
    /// failed.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        FontRegistrar.registerBundledFonts()
        let name: String
        switch weight {
        case .ultraLight, .thin, .light: name = "Cove-Regular"
        case .medium: name = "Cove-SemiBold"
        case .semibold, .bold, .heavy, .black: name = "Cove-Bold"
        default: name = "Cove-Medium"
        }
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight)
    }

    /// Geist Serif for titles (screen names, catalog headings). The bundled
    /// cut has a single weight; falls back to the system serif if it failed
    /// to register.
    static func display(_ size: CGFloat) -> Font {
        FontRegistrar.registerBundledFonts()
        let name = "GeistSerifVF-Regular"
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }
}

// MARK: - Glass surfaces

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Clear glass for controls floating over wallpaper images.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.clear.interactive(), in: shape)
        } else {
            background(VisualEffectBackground(material: .hudWindow))
                .clipShape(shape)
        }
    }

    /// Regular glass for chrome that sits on the window background.
    @ViewBuilder
    func tintedGlassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(VisualEffectBackground(material: .popover))
                .clipShape(shape)
        }
    }

    func pointerOnHover() -> some View {
        modifier(PointerOnHover())
    }
}

/// Pointing-hand cursor while hovered. Unbalanced `NSCursor.push/pop` left
/// the hand stuck whenever a hovered control vanished (sheet dismissed,
/// chips hidden) before the mouse exited, so the pop is tracked explicitly.
private struct PointerOnHover: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

// MARK: - Components

/// Capsule button for the window header, shaped like a macOS 26 toolbar item.
struct ToolbarButton: View {
    let symbol: String
    var title: String? = nil
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                if let title {
                    Text(title)
                        .font(Design.font(12, weight: .medium))
                }
            }
            .foregroundStyle(isActive || hovering ? Design.ink : Design.inkSecondary)
            .padding(.horizontal, title == nil ? 0 : 12)
            .frame(minWidth: 30, minHeight: 30)
            .tintedGlassSurface(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(title ?? help)
    }
}

/// Small capsule button that floats over an image (Change, Desktop, Lock Screen).
struct OverlayButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(title)
                    .font(Design.font(11.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassSurface(Capsule())
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .pointerOnHover()
    }
}

struct WallpsToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.success)

            Text(message)
                .font(Design.font(12.5, weight: .medium))
                .foregroundStyle(Design.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .tintedGlassSurface(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 4)
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view: NSView

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = 0
            view = glassView
        } else {
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            view = visualEffectView
        }

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
    }
}
