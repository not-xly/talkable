import SwiftUI

/// Shared design tokens and surfaces for the setup guide and preferences.
///
/// Visual language: the same "liquid glass" as the dictation HUD
/// (HUDController / desktop/ui/hud.html). On macOS 26+ cards and the main
/// buttons use SwiftUI's `glassEffect` / glass button styles; on macOS 14–15
/// they fall back to `.ultraThinMaterial` with rounded corners and a thin
/// edge. Colours are semantic so light/dark mode and "Increase contrast" are
/// handled by the system; "Reduce transparency" swaps glass for a solid fill.
enum XlyTheme {
    // Palette (semantic, adapts to light/dark and accessibility settings)
    static let text = Color.primary
    static let textSecondary = Color.secondary
    static let border = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.06)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.16)
    static let danger = Color.red
    static let warnText = Color.orange

    /// Corner radius of glass cards (the HUD uses 24 for a single-line pill;
    /// multi-row cards read better slightly tighter).
    static let cardRadius: CGFloat = 18

    static let mono = Font.system(.body, design: .monospaced)
}

/// Window backdrop: the system window colour with a faint accent wash, so the
/// glass cards have something to refract (mirrors the desktop UI's page wash).
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                LinearGradient(
                    colors: [XlyTheme.accent.opacity(0.10), .clear, Color.green.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// A small tag ("Required" / "Optional") shown next to setup items.
struct ChipView: View {
    enum Kind {
        case required
        case optional

        var label: String {
            switch self {
            case .required: return "Required"
            case .optional: return "Optional"
            }
        }

        var foreground: Color {
            switch self {
            case .required: return XlyTheme.accent
            case .optional: return XlyTheme.textSecondary
            }
        }

        var background: Color {
            switch self {
            case .required: return XlyTheme.accentSoft
            case .optional: return XlyTheme.hover
            }
        }
    }

    let kind: Kind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(kind.background, in: Capsule())
    }
}

/// Glass card: the standard surface of the design.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 14
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: XlyTheme.cardRadius, style: .continuous)
        let padded = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)

        if reduceTransparency {
            padded
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(XlyTheme.border))
        } else if #available(macOS 26.0, *) {
            padded
                .glassEffect(.regular, in: shape)
        } else {
            padded
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

/// Primary action: prominent glass on macOS 26+, prominent bordered before.
struct PrimaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

/// Secondary action: glass on macOS 26+, bordered before.
struct SecondaryButtonModifier: ViewModifier {
    var large = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).controlSize(large ? .large : .regular)
        } else {
            content.buttonStyle(.bordered).controlSize(large ? .large : .regular)
        }
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        modifier(GlassCard(padding: padding))
    }

    func primaryButton() -> some View {
        modifier(PrimaryButtonModifier())
    }

    func secondaryButton(large: Bool = false) -> some View {
        modifier(SecondaryButtonModifier(large: large))
    }
}
