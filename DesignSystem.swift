import AppKit
import CoreText
import SwiftUI

// MARK: - Font Registrar

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

// MARK: - Design System

enum Design {
    // ── Monochromatic Dark Palette ─────────────────────────────────────
    static let background = Color(red: 0.051, green: 0.051, blue: 0.058) // #0D0D0F
    static let surface = Color(red: 0.090, green: 0.090, blue: 0.102)    // #17171A
    static let surfaceRaised = Color(red: 0.135, green: 0.135, blue: 0.150) // #222226
    static let surfaceOverlay = Color(red: 0.175, green: 0.175, blue: 0.195) // #2C2C32
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.18)
    static let hairlineSubtle = Color.white.opacity(0.04)

    static let ink = Color(red: 0.980, green: 0.980, blue: 0.985)
    static let inkSecondary = Color(red: 0.720, green: 0.720, blue: 0.760)
    static let inkTertiary = Color(red: 0.480, green: 0.480, blue: 0.520)
    static let inkMuted = Color(red: 0.320, green: 0.320, blue: 0.360)

    static let accent = Color.white
    static let accentGlow = Color.white.opacity(0.15)
    static let accentInk = Color(red: 0.05, green: 0.05, blue: 0.06) // Deep black text on white accent

    // ── Typography: Geist Mono ────────────────────────────────────────
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        FontRegistrar.registerBundledFonts()

        let postScriptName: String
        switch weight {
        case .ultraLight, .thin:
            postScriptName = "GeistMono-Thin"
        case .light:
            postScriptName = "GeistMono-Light"
        case .regular:
            postScriptName = "GeistMono-Regular"
        case .medium:
            postScriptName = "GeistMono-Medium"
        case .semibold:
            postScriptName = "GeistMono-SemiBold"
        case .bold:
            postScriptName = "GeistMono-Bold"
        case .heavy, .black:
            postScriptName = "GeistMono-Black"
        default:
            postScriptName = "GeistMono-Regular"
        }

        if NSFont(name: postScriptName, size: size) != nil {
            return .custom(postScriptName, size: size)
        }
        if NSFont(name: "Geist Mono", size: size) != nil {
            return .custom("Geist Mono", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Reusable UI Components

struct SectionLabel: View {
    let text: String
    var trailing: AnyView? = nil

    init(_ text: String, trailing: AnyView? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(Design.mono(9.5, .semibold))
                .tracking(2.0)
                .foregroundStyle(Design.inkTertiary)
            Spacer()
            trailing
        }
    }
}

struct GhostIconButton: View {
    let symbol: String
    let help: String
    var badge: String? = nil
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                if let badge {
                    Text(badge.uppercased())
                        .font(Design.mono(9.5, .semibold))
                        .tracking(1.0)
                }
            }
            .foregroundStyle(hovering ? Design.ink : Design.inkSecondary)
            .padding(.horizontal, badge != nil ? 10 : 8)
            .frame(height: 28)
            .background(hovering ? Design.surfaceRaised : Design.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(hovering ? Design.hairlineStrong : Design.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
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
                    .font(Design.mono(10.5, .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Design.accentInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(hovering ? Color(white: 0.90) : Color.white, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressing ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressing)
        .shadow(color: isEnabled && hovering ? Color.white.opacity(0.25) : .clear, radius: 10, y: 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(configuration.isOn ? Color.white : Design.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(configuration.isOn ? Color.clear : Design.hairlineStrong, lineWidth: 1)
                    )
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(configuration.isOn ? Design.accentInk : Color.white.opacity(0.75))
                    .frame(width: 16, height: 16)
                    .offset(x: configuration.isOn ? 18 : 2)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Toggle"))
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
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
                        .font(Design.mono(9.5, selected ? .semibold : .medium))
                        .tracking(0.8)
                        .foregroundStyle(selected ? Design.ink : Design.inkTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? Design.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(Design.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.hairline, lineWidth: 1))
    }
}

struct StatusDot: View {
    let filled: Bool
    var isGlowing: Bool = false

    var body: some View {
        ZStack {
            if filled && isGlowing {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .blur(radius: 2)
            }
            Circle()
                .strokeBorder(filled ? Color.white : Design.inkMuted, lineWidth: 1.2)
                .background(Circle().fill(filled ? Color.white : Color.clear))
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
