import SwiftUI
import AppKit

/// First-launch setup guide: light, type, permissions, shortcuts.
struct SetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = SetupGuide.startStep
    @State private var forward = true
    private let steps = 7
    /// Where the guide opens (the snapshot driver jumps to a step).
    nonisolated(unsafe) static var startStep = 0

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 0) {
                ZStack {
                    content
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                footer
            }
        }
        .frame(width: 680, height: 540)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: WelcomeStep()
        case 1: AppearanceStep()
        case 2: TypographyStep()
        case 3: SmartFillStep()
        case 4: ClaudeStep()
        case 5: PermissionsStep()
        default: ShortcutsStep()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(-1) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            } else {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.haloSecondary)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.haloAction : Color.primary.opacity(0.15))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .animation(Motion.snappy, value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step + 1) of \(steps)")
            Spacer()
            Button(step == steps - 1 ? "Enter Halo" : "Continue") {
                if step == steps - 1 { finish() } else { go(1) }
            }
            .buttonStyle(.glassProminent)
            .tint(Color.haloAction)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .frame(height: 68)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(Motion.gentle) { step = max(0, min(steps - 1, step + delta)) }
    }

    private func finish() {
        Preferences.shared.hasCompletedSetup = true
        dismiss()
    }
}

private struct StepHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.haloText)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.haloSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }
}

private struct SmartFillStep: View {
    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Smarter Tab (optional)",
                       subtitle: "Halo can run a small open-source code model on your Mac. Free, offline and private — your code never leaves this computer.")
            SmartFillControls()
                .frame(width: 480)
            Text("You can skip this and download it later in Settings. Without it, Tab uses Halo’s built-in pattern engine.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.haloTertiary)
                .multilineTextAlignment(.center)
                .frame(width: 440)
        }
        .padding(.top, 24)
    }
}

private struct ClaudeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Work with Claude (optional)",
                       subtitle: "Connect Claude Desktop or Claude Code, and Claude can see what you’re working on, edit files and run code in Halo.")
            ClaudeConnectRows(carded: true)
                .frame(width: 480)
            Text("Connecting turns on Claude access. Choose what Claude may do — and turn it off — in Settings → Claude.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.haloTertiary)
                .multilineTextAlignment(.center)
                .frame(width: 440)
        }
        .padding(.top, 24)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            StepHeader(title: "Welcome to Halo",
                       subtitle: "A quiet, fast editor made for the Mac. Let’s take a minute to make it feel like yours.")
        }
        .padding(.top, 20)
    }
}

private struct AppearanceStep: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(title: "Choose your light", subtitle: "Daybreak for bright rooms, Nightfall for late hours — or let macOS decide.")
            HStack(spacing: 16) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceCard(mode: mode, selected: prefs.appearance == mode) {
                        withAnimation(Motion.gentle) { prefs.appearance = mode }
                    }
                }
            }
        }
        .padding(.top, 36)
    }
}

private struct AppearanceCard: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(width: 170, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.haloAction : Color.haloHairline, lineWidth: selected ? 2 : 1))
                    .shadow(color: .black.opacity(selected ? 0.12 : 0.05), radius: selected ? 10 : 4, y: 3)
                Text(mode.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.haloText : Color.haloSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .daybreak: CodeSample(dark: false)
        case .nightfall: CodeSample(dark: true)
        case .system:
            HStack(spacing: 0) {
                CodeSample(dark: false)
                CodeSample(dark: true).offset(x: -85).frame(width: 85).clipped()
            }
        }
    }
}

/// A tiny static code preview drawn with the real syntax palette.
private struct CodeSample: View {
    let dark: Bool
    var fontSize: CGFloat = 9.5

    private func c(_ color: NSColor) -> Color {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out = Color.clear
        appearance.performAsCurrentDrawingAppearance { out = Color(nsColor: color.usingColorSpace(.sRGB) ?? color) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.55) {
            line([("// light, everywhere", c(SyntaxPalette.comment))])
            line([("func ", c(SyntaxPalette.keyword)), ("shine", c(SyntaxPalette.function)), ("(", c(Palette.text)), ("at", c(Palette.text)), (": ", c(Palette.text)), ("Hour", c(SyntaxPalette.type)), (") {", c(Palette.text))])
            line([("    let ", c(SyntaxPalette.keyword)), ("glow", c(Palette.text)), (" = ", c(Palette.text)), ("0.8", c(SyntaxPalette.number))])
            line([("    return ", c(SyntaxPalette.keyword)), ("\"halo\"", c(SyntaxPalette.string))])
            line([("}", c(Palette.text))])
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(Palette.editorBackground))
    }

    private func line(_ parts: [(String, Color)]) -> some View {
        parts.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
            .font(.system(size: fontSize, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
    }
}

private struct TypographyStep: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Make it comfortable", subtitle: "Pick a size and spacing that are easy on your eyes. You can change these anytime with ⌘= and ⌘−.")
            CodeSample(dark: NSApp.effectiveAppearance.isDark, fontSize: prefs.fontSize)
                .frame(width: 440, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.haloHairline))
                .animation(Motion.snappy, value: prefs.fontSize)
            VStack(spacing: 14) {
                sliderRow("Font size", value: Binding(get: { Double(prefs.fontSize) }, set: { prefs.fontSize = CGFloat($0.rounded(toPlaces: 1)) }), range: 11...20, step: 0.5, display: String(format: "%.1f pt", prefs.fontSize))
                sliderRow("Line spacing", value: Binding(get: { Double(prefs.lineSpacing) }, set: { prefs.lineSpacing = CGFloat($0.rounded(toPlaces: 2)) }), range: 1.2...2.0, step: 0.05, display: String(format: "%.2f×", prefs.lineSpacing))
                Toggle("Wrap long lines", isOn: $prefs.wordWrap)
                    .toggleStyle(.switch)
                    .font(.system(size: 13))
                    .frame(width: 440, alignment: .leading)
            }
        }
        .padding(.top, 28)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13)).foregroundStyle(Color.haloText).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(display).font(.system(size: 12).monospacedDigit()).foregroundStyle(Color.haloSecondary).frame(width: 56, alignment: .trailing)
        }
        .frame(width: 440)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10, Double(places))
        return (self * m).rounded() / m
    }
}

/// Explains (and links to) the macOS privacy settings Halo benefits from.
private struct PermissionsStep: View {
    @State private var fullDiskAccess = PermissionsStep.hasFullDiskAccess

    static var hasFullDiskAccess: Bool {
        // Only readable when Full Disk Access is granted.
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: probe) && (try? Data(contentsOf: URL(fileURLWithPath: probe), options: .mappedIfSafe)) != nil
    }

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "A few permissions", subtitle: "macOS protects your folders. Halo only asks for what it needs, and everything stays on your Mac.")
            VStack(spacing: 10) {
                PermissionRow(
                    symbol: "folder.badge.person.crop",
                    title: "Folder access",
                    detail: "The first time you open a project in Desktop, Documents or Downloads, macOS will ask. Choose Allow.",
                    status: .info)
                PermissionRow(
                    symbol: "externaldrive.badge.checkmark",
                    title: "Full Disk Access (recommended)",
                    detail: "Lets the built-in terminal and search reach every project without repeated prompts. Turn on Halo in the list.",
                    status: fullDiskAccess ? .granted : .action("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    })
                PermissionRow(
                    symbol: "terminal",
                    title: "Developer tools",
                    detail: "Git status and the terminal use your installed tools. If git is missing, run xcode-select --install.",
                    status: Git.executable != nil ? .granted : .action("Install") {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
                        p.arguments = ["--install"]
                        try? p.run()
                    })
            }
            .frame(width: 520)
        }
        .padding(.top, 28)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess = Self.hasFullDiskAccess
        }
    }
}

private struct PermissionRow: View {
    enum Status { case info, granted, action(String, () -> Void) }
    let symbol: String
    let title: String
    let detail: String
    let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.haloSky)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.haloText)
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.haloSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch status {
            case .info:
                EmptyView()
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.haloAdded)
            case .action(let label, let run):
                Button(label, action: run).buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.haloRaised.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.haloHairline))
    }
}

private struct ShortcutsStep: View {
    private let items: [(String, String, String)] = [
        ("⇥", "Accept Fill", "Gray suggestions learned from your own code"),
        ("⌘P", "Quick Open", "Jump to any file by typing a few letters"),
        ("⌘R", "Run", "Python, C, Swift, Go, JS and more — one key"),
        ("F5", "Debug", "Breakpoints, variables and stepping"),
        ("⇧⌘F", "Search in Project", "Find text across all files"),
        ("⇧⌘P", "Command Palette", "Every action, one keystroke away"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Your shortcuts", subtitle: "These are all you need to remember. Everything else lives in ⇧⌘P.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.0) { keys, title, detail in
                    HStack(spacing: 12) {
                        Kbd(keys).frame(width: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.haloText)
                            Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.haloSecondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.haloRaised.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.haloHairline))
                }
            }
            .frame(width: 560)
        }
        .padding(.top, 28)
    }
}
