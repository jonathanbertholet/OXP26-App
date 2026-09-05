import SwiftUI

enum OxpTheme {
    static let accent = Color(red: 0.443, green: 0.294, blue: 0.404)
    static let warm = Color(red: 0.965, green: 0.957, blue: 0.949)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)

    static func roomColor(_ name: String) -> Color {
        switch name {
        case "Hall 6.A": Color(red: 0.75, green: 0.33, blue: 0.35)
        case "Hall 6.B": Color(red: 0.86, green: 0.52, blue: 0.22)
        case "Hall 6.C": Color(red: 0.20, green: 0.55, blue: 0.48)
        case "Hall 6.D": Color(red: 0.33, green: 0.45, blue: 0.72)
        case "Hall 6.E": Color(red: 0.55, green: 0.38, blue: 0.70)
        case "Hall 7.A": Color(red: 0.18, green: 0.47, blue: 0.62)
        case "Hall 7.B": Color(red: 0.62, green: 0.28, blue: 0.48)
        case "Auditorium 4000 A": Color(red: 0.45, green: 0.22, blue: 0.40)
        case "Auditorium 4000 B": Color(red: 0.52, green: 0.28, blue: 0.46)
        case "Auditorium 4000 C": Color(red: 0.58, green: 0.32, blue: 0.50)
        case "Auditorium 4000 D": Color(red: 0.64, green: 0.36, blue: 0.54)
        case "Auditorium 2000 A": Color(red: 0.22, green: 0.38, blue: 0.58)
        case "Auditorium 2000 B": Color(red: 0.26, green: 0.44, blue: 0.64)
        case "Auditorium 2000 C": Color(red: 0.30, green: 0.50, blue: 0.70)
        case "Auditorium 500": Color(red: 0.40, green: 0.58, blue: 0.42)
        case "Education Village": Color(red: 0.18, green: 0.58, blue: 0.52)
        case "Main stage": Color(red: 0.45, green: 0.22, blue: 0.40)
        case "Auditorium 2000": Color(red: 0.22, green: 0.38, blue: 0.58)
        default: accent
        }
    }
}

extension View {
    func oxpGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)) -> some View {
        glassEffect(.regular, in: shape)
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? Color.white : .primary)
            .background(selected ? OxpTheme.accent : Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    func oxpCard() -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(OxpTheme.accent.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.025), radius: 10, y: 4)
    }
}


/// A quiet brand wash behind native lists and scrolling content.
struct OxpBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .overlay {
                LinearGradient(
                    colors: [OxpTheme.accent.opacity(0.08), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct OxpIconTile: View {
    let symbol: String
    var color: Color = OxpTheme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.10), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct OxpSectionHeading: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title).font(.title3.bold())
        } icon: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OxpTheme.accentInk)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct OxpPageIntro: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OxpIconTile(symbol: symbol, color: OxpTheme.accentInk)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension OxpTheme {
    /// Keep text accents legible on dark surfaces without changing filled controls.
    static let accentInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.83, green: 0.66, blue: 0.78, alpha: 1)
            : UIColor(red: 0.443, green: 0.294, blue: 0.404, alpha: 1)
    })

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.34, green: 0.20, blue: 0.33), accent,
                 Color(red: 0.53, green: 0.34, blue: 0.46)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension View {
    func oxpBackground() -> some View {
        background { OxpBackground() }
    }

    func oxpHero() -> some View {
        background {
            OxpTheme.heroGradient
                .overlay(alignment: .topTrailing) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .strokeBorder(.white.opacity(0.08), lineWidth: 28)
                            .frame(width: 190, height: 190)
                            .offset(x: 55, y: -75)
                        Circle()
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                            .frame(width: 230, height: 230)
                            .offset(x: 75, y: -95)
                    }
                }
            .clipShape(.rect(cornerRadius: 24))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
