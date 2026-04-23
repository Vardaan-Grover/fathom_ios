import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var hexValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&hexValue)

        let r = Double((hexValue >> 16) & 0xFF) / 255.0
        let g = Double((hexValue >> 8) & 0xFF) / 255.0
        let b = Double(hexValue & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}