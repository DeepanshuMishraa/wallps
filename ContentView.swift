import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ImportTarget {
    case desktop
    case login

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .login: return "Lock screen"
        }
    }

    var subtitle: String {
        switch self {
        case .desktop: return "Visible after you sign in"
        case .login: return "Visible before you sign in"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "macbook"
        case .login: return "lock.display"
        }
    }
}

struct ContentView: View {
    @State private var desktopImage: URL?
    @State private var loginImage: URL?
    @State private var isImporting = false
    @State private var pendingTarget: ImportTarget = .desktop
    @State private var isApplying = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var alert: WallpaperService.AlertMessage?
    @State private var launchAtLogin = false
    @State private var showingLoginPrompt = false
    @State private var didAutoReapply = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 660, minHeight: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch pendingTarget {
            case .desktop: desktopImage = url
            case .login: loginImage = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setWallpapers)) { _ in
            applyWallpapers()
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Allow Wallps to launch at login?",
            isPresented: $showingLoginPrompt,
            titleVisibility: .visible
        ) {
            Button("Allow") {
                Task {
                    do {
                        try LoginItemManager.enable()
                    } catch {
                        launchAtLogin = false
                        alert = WallpaperService.AlertMessage(
                            title: "Auto-start unavailable",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            Button("Not now", role: .cancel) {
                launchAtLogin = false
            }
        } message: {
            Text("Wallps starts hidden at every login and keeps swapping your desktop and lock screen wallpapers automatically. You can turn this off anytime.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wallps")
                    .font(.system(size: 17, weight: .bold))
                Text("Separate wallpapers for your desktop and lock screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                wallpaperCard(target: .desktop, image: desktopImage)
                wallpaperCard(target: .login, image: loginImage)
            }
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Launch at login")
                        .font(.callout.weight(.medium))
                    Text("Starts hidden and keeps the lock-screen swap armed after every reboot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .onAppear { launchAtLogin = LoginItemManager.isEnabled }
            .onChange(of: launchAtLogin) { enabled in
                guard enabled else {
                    Task { try? LoginItemManager.disable() }
                    return
                }
                guard !LoginItemManager.isEnabled else { return }
                showingLoginPrompt = true
            }
        }
        .padding(22)
        .onAppear { autoReapplySavedChoices() }
    }

    private func autoReapplySavedChoices() {
        guard !didAutoReapply else { return }
        didAutoReapply = true

        let savedDesktop = WallpaperSwitcher.shared.savedDesktopURL
        let savedLogin = WallpaperSwitcher.shared.savedLoginURL
        let desktopIsValid = savedDesktop.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let loginIsValid = savedLogin.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        if loginIsValid, let savedLogin {
            loginImage = savedLogin
        } else {
            loginImage = WallpaperService.currentLoginImageURL()
        }

        if desktopIsValid, let savedDesktop {
            desktopImage = savedDesktop
        } else {
            desktopImage = NSScreen.screens.first.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                ?? savedDesktop
        }

        guard desktopIsValid, loginIsValid, let savedDesktop, let savedLogin else { return }
        Task {
            isApplying = true
            statusMessage = "Reapplying your wallpapers…"
            statusIsError = false
            do {
                statusMessage = try await WallpaperService.apply(desktop: savedDesktop, login: savedLogin, legacyInstall: false)
                WallpaperSwitcher.shared.arm(desktop: savedDesktop, login: savedLogin)
            } catch {
                statusMessage = "Could not reapply your saved wallpapers."
                statusIsError = true
            }
            isApplying = false
        }
    }

    private func wallpaperCard(target: ImportTarget, image: URL?) -> some View {
        WallpaperCardView(
            target: target,
            url: image,
            onPick: { chooseImage(for: target) },
            onAcceptImage: { url in
                switch target {
                case .desktop: desktopImage = url
                case .login: loginImage = url
                }
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Group {
                if let message = statusMessage {
                    Label(message, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .orange : .secondary)
                        .transition(.opacity)
                } else {
                    Text("Pick two images, then set them. Lock your Mac (⌃⌘Q) to preview.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusMessage)
            Spacer()
            Button {
                applyWallpapers()
            } label: {
                HStack(spacing: 7) {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                        Text("Applying")
                    } else {
                        Text("Set wallpapers")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(minWidth: 138)
            }
            .buttonStyle(ProminentButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(desktopImage == nil || loginImage == nil || isApplying)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func chooseImage(for target: ImportTarget) {
        pendingTarget = target
        isImporting = true
    }

    private func applyWallpapers() {
        guard let desktopImage, let loginImage else { return }
        Task {
            isApplying = true
            statusMessage = "Applying wallpapers…"
            statusIsError = false
            do {
                statusMessage = try await WallpaperService.apply(desktop: desktopImage, login: loginImage)
                WallpaperSwitcher.shared.arm(desktop: desktopImage, login: loginImage)
            } catch {
                statusMessage = "Could not apply both wallpapers."
                statusIsError = true
                alert = WallpaperService.AlertMessage(title: "Wallpaper setup failed", message: error.localizedDescription)
            }
            isApplying = false
        }
    }
}

private struct WallpaperCardView: View {
    let target: ImportTarget
    let url: URL?
    let onPick: () -> Void
    let onAcceptImage: (URL) -> Void

    @State private var previewImage: NSImage?
    @State private var hovering = false
    @State private var dropping = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Choose an image")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
            bottomBar
                .opacity(hovering ? 1 : 0.8)
        }
        .frame(height: 214)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hovering)
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 14 : 5, y: hovering ? 6 : 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .opacity(dropping ? 1 : 0)
        )
        .onHover { hovering = $0 }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                WallpaperImageStore.load(url) { image in
                    if image != nil {
                        onAcceptImage(url)
                    }
                }
            }
            return true
        }
        .onAppear { loadImage() }
        .onChange(of: url) { _ in loadImage() }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Label(target.title, systemImage: target.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let url {
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            Button(action: onPick) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.92))
                    Image(systemName: url == nil ? "plus" : "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black.opacity(0.65))
                }
                .frame(width: 27, height: 27)
            }
            .buttonStyle(PressScaleButtonStyle())
            .help(url == nil ? "Choose an image" : "Choose a different image")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func loadImage() {
        previewImage = nil
        guard let url else { return }
        if let cached = WallpaperImageStore.cachedImage(for: url) {
            withAnimation(.easeOut(duration: 0.25)) {
                previewImage = cached
            }
            return
        }
        WallpaperImageStore.load(url) { image in
            if let image {
                withAnimation(.easeOut(duration: 0.25)) {
                    previewImage = image
                }
            }
        }
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}