import SwiftUI

extension Color {
    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        var n: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&n)
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8)  & 0xFF) / 255,
            blue:  Double( n        & 0xFF) / 255
        )
    }
}
