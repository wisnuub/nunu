import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
