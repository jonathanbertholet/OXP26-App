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
