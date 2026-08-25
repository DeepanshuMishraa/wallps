import AppKit
import CoreText
import SwiftUI

// MARK: - Font Registrar for Geist Mono

enum FontRegistrar {
    private static var hasRegistered = false
    private static let bundledFontName = "GeistMono-Variable"

    static func registerBundledFonts() {
        guard !hasRegistered else { return }
        hasRegistered = true

        var fontURLs: [URL] = []

        if let bundleNested = Bundle.main.url(
            forResource: bundledFontName,
            withExtension: "ttf",
            subdirectory: "Resources/Fonts"
        ) {
            fontURLs.append(bundleNested)
        }

        if let bundleRoot = Bundle.main.url(forResource: bundledFontName, withExtension: "ttf") {
            fontURLs.append(bundleRoot)
        }

        let userFontsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts")
            .appendingPathComponent("\(bundledFontName).ttf")
        if FileManager.default.fileExists(atPath: userFontsURL.path) {
            fontURLs.append(userFontsURL)
        }

        let systemFontsURL = URL(fileURLWithPath: "/Library/Fonts/\(bundledFontName).ttf")
        if FileManager.default.fileExists(atPath: systemFontsURL.path) {
            fontURLs.append(systemFontsURL)
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

// MARK: - Design Tokens (Billion-Dollar Precision Monospace Aesthetic)

enum Design {
    // ── High-Contrast Precision Monochromatic Palette ─────────────────
    static let background = Color.dynamic(
        light: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0), // #F5F5F7
        dark: NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.040, alpha: 1.0) // #09090A (Pure Deep Obsidian)
    )

    static let surface = Color.dynamic(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.085, alpha: 1.0)  // #131316
    )

    static let surfaceRaised = Color.dynamic(
        light: NSColor(calibratedRed: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.135, alpha: 1.0)   // #1F1F22
    )

    static let surfaceHighlight = Color.dynamic(
        light: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.90, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.20, alpha: 1.0)
    )

    static let hairline = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.09)
    )

    static let hairlineStrong = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.20)
    )

    static let hairlineSubtle = Color.dynamic(
        light: NSColor.black.withAlphaComponent(0.04),
        dark: NSColor.white.withAlphaComponent(0.05)
    )

    static let ink = Color.dynamic(
        light: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
    )

    static let inkSecondary = Color.dynamic(
        light: NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.38, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.70, alpha: 1.0)
    )

    static let inkTertiary = Color.dynamic(
        light: NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.40, green: 0.40, blue: 0.45, alpha: 1.0)
    )

    static let accent = Color.dynamic(
        light: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1.0),
        dark: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    static let accentInk = Color.dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
    )

    static let success = Color.dynamic(
        light: NSColor(calibratedRed: 0.08, green: 0.65, blue: 0.38, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.50, alpha: 1.0)
    )

    static let warning = Color.dynamic(
        light: NSColor(calibratedRed: 0.88, green: 0.52, blue: 0.08, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.20, alpha: 1.0)
    )

    static let error = Color.dynamic(
        light: NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.22, alpha: 1.0),
        dark: NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.38, alpha: 1.0)
    )

    // ── Typography: 100% Pure Geist Mono Everywhere ────────────────────
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        FontRegistrar.registerBundledFonts()

        let postScriptName: String
        switch weight {
        case .ultraLight, .thin: postScriptName = "GeistMono-Thin"
        case .light: postScriptName = "GeistMono-Light"
        case .regular: postScriptName = "GeistMono-Regular"
        case .medium: postScriptName = "GeistMono-Medium"
        case .semibold: postScriptName = "GeistMono-SemiBold"
        case .bold, .heavy, .black: postScriptName = "GeistMono-Bold"
        default: postScriptName = "GeistMono-Regular"
        }

        if NSFont(name: postScriptName, size: size) != nil {
            return .custom(postScriptName, size: size)
        }
        if NSFont(name: "Geist Mono", size: size) != nil {
            return .custom("Geist Mono", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size, weight: weight)
    }
}

// MARK: - Pointer Cursor Extension

extension View {
    func pointerOnHover() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Precision Minimalist Components

struct SectionLabel: View {
    let text: String
    var code: String? = nil

    init(_ text: String, code: String? = nil) {
        self.text = text
        self.code = code
    }

    var body: some View {
        HStack(spacing: 6) {
            if let code {
                Text("// \(code)")
                    .font(Design.font(10, weight: .bold))
                    .foregroundStyle(Design.inkTertiary)
            }
            Text(text.uppercased())
                .font(Design.font(10.5, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Design.ink)
            Spacer()
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    var isLoading = false
    var keyEquivalent: KeyEquivalent? = nil
    let action: () -> Void

    @State private var hovering = false
    @State private var pressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if let key = keyEquivalent {
                buttonBody.keyboardShortcut(key, modifiers: [.command])
            } else {
                buttonBody
            }
        }
    }

    private var buttonBody: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Design.accentInk)
                }
                Text(title.uppercased())
                    .font(Design.font(11, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Design.accentInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Design.accent)
                    .opacity(hovering ? 0.90 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Design.hairlineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(pressing ? 0.96 : (hovering && isEnabled ? 1.01 : 1.0))
        .opacity(isEnabled ? 1 : 0.35)
        .pointerOnHover()
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: pressing)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct GhostIconButton: View {
    let symbol: String
    let text: String?
    let help: String
    let action: () -> Void

    init(symbol: String, text: String? = nil, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.text = text
        self.help = help
        self.action = action
    }

    @State private var hovering = false
    @State private var pressing = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                if let text {
                    Text(text.uppercased())
                        .font(Design.font(10, weight: .bold))
                        .tracking(1.2)
                }
            }
            .foregroundStyle(hovering ? Design.ink : Design.inkSecondary)
            .padding(.horizontal, text != nil ? 10 : 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Design.surfaceRaised : Design.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(hovering ? Design.hairlineStrong : Design.hairline, lineWidth: 1)
            )
            .scaleEffect(pressing ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .pointerOnHover()
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? Design.accent : Design.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(configuration.isOn ? Color.clear : Design.hairlineStrong, lineWidth: 1)
                    )
                    .frame(width: 34, height: 18)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(configuration.isOn ? Design.accentInk : Design.inkSecondary)
                    .frame(width: 12, height: 12)
                    .offset(x: configuration.isOn ? 18 : 3)
            }
        }
        .buttonStyle(.plain)
        .pointerOnHover()
    }
}

struct SegmentedSwitch<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(label(option).uppercased())
                        .font(Design.font(9.5, weight: selected ? .bold : .medium))
                        .tracking(1.0)
                        .foregroundStyle(selected ? Design.ink : Design.inkTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selected
                                ? RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Design.surfaceRaised)
                                : nil
                        )
                        .overlay(
                            selected
                                ? RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Design.hairlineStrong, lineWidth: 1)
                                : nil
                        )
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }
        }
        .padding(2.5)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Design.hairline, lineWidth: 1))
    }
}

struct StatusDot: View {
    let filled: Bool
    var isGlowing: Bool = false
    var customColor: Color? = nil

    var body: some View {
        let activeColor = customColor ?? (filled ? Design.ink : Design.inkTertiary)
        ZStack {
            if filled && isGlowing {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(activeColor.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .blur(radius: 2)
            }
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .strokeBorder(filled ? activeColor : Design.inkTertiary, lineWidth: 1.2)
                .background(RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(filled ? activeColor : Color.clear))
                .frame(width: 6, height: 6)
        }
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
