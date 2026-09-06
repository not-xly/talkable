import SwiftUI

/// Shared design tokens: the app's palette and type styles, used by the
/// setup guide and preferences so both platforms share one visual language.
enum XlyTheme {
    // Palette
    static let background = Color(hex: 0xF7F7F5)      // general background
    static let surface = Color(hex: 0xFFFFFF)         // floating surface
    static let text = Color(hex: 0x37352F)            // primary text
    static let textSecondary = Color(hex: 0x787774)   // secondary text
    static let placeholder = Color(hex: 0xB9B7B2)
    static let border = Color(hex: 0xE9E9E7)
    static let hover = Color(hex: 0x37352F, alpha: 0.06)
    static let active = Color(hex: 0x37352F, alpha: 0.09)
    static let accent = Color(hex: 0x2383E2)
    static let accentSoft = Color(hex: 0x2383E2, alpha: 0.14)
    static let accentHover = Color(hex: 0x1E73C6)
    static let danger = Color(hex: 0xE03E3E)
    static let dangerSoft = Color(hex: 0xE03E3E, alpha: 0.10)
    static let warnBackground = Color(hex: 0xFBF3DB)
    static let warnText = Color(hex: 0x5F4C1D)
    static let warnBorder = Color(hex: 0xF0E2B6)
    static let dark = Color(hex: 0x37352F)            // dark buttons
    static let darkHover = Color(hex: 0x000000)

    static let mono = Font.system(.body, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
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
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(kind.background, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The primary button style: dark surface, white text (xlyUI "dark button").
struct DarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? XlyTheme.darkHover : XlyTheme.dark)
            )
    }
}

/// Secondary button: white surface with a hairline border.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(XlyTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? XlyTheme.hover : XlyTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(XlyTheme.border)
            )
    }
}

/// White card with hairline border, the standard surface of the design.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XlyTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(XlyTheme.border)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        modifier(CardBackground(padding: padding))
    }
}
