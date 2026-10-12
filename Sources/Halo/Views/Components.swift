import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// A small, quiet icon button with a proper hit area and hover/press states.
struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 12
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Color.haloSky : (hovering ? Color.haloText : Color.haloSecondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.haloSky.opacity(0.14) : (hovering ? Color.primary.opacity(0.06) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Press feedback without layout shift: opacity + a hair of scale.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Keyboard shortcut chip, e.g. ⌘P.
struct Kbd: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.haloSecondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.haloHairline))
    }
}

/// Halo's mark, drawn flat: a ring over a caret.
struct HaloMark: View {
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: size * 0.12) {
            Ellipse()
                .stroke(Color.haloText.opacity(0.85), lineWidth: max(2, size * 0.075))
                .frame(width: size, height: size * 0.32)
            Capsule()
                .fill(Color.haloAction)
                .frame(width: max(3, size * 0.08), height: size * 0.42)
        }
        .accessibilityHidden(true)
    }
}

/// Background for Halo's quiet spaces (welcome, setup).
struct SkyBackground: View {
    var body: some View {
        Color.haloChrome.ignoresSafeArea()
    }
}

/// Highlights matched character positions (UTF-16 offsets) in a string.
func highlighted(_ text: String, positions: [Int], offset: Int = 0, base: Color, highlight: Color) -> AttributedString {
    var out = AttributedString(text)
    out.foregroundColor = base
    guard !positions.isEmpty else { return out }
    let utf16 = text.utf16
    for p in positions {
        let local = p - offset
        guard local >= 0, local < utf16.count else { continue }
        let start = String.Index(utf16Offset: local, in: text)
        let end = text.index(after: start)
        if let lower = AttributedString.Index(start, within: out), let upper = AttributedString.Index(end, within: out) {
            out[lower..<upper].foregroundColor = highlight
            out[lower..<upper].font = .system(size: 13, weight: .semibold)
        }
    }
    return out
}
