import SwiftUI

enum GardenShapeCategory: Int, CaseIterable {
    case empty = 0
    case sprout
    case leaf
    case flower
    case tree

    static func category(for duration: TimeInterval) -> GardenShapeCategory {
        if duration <= 0 { return .empty }
        if duration < 15 * 60 { return .sprout }
        if duration < 30 * 60 { return .leaf }
        if duration < 60 * 60 { return .flower }
        return .tree
    }
}

struct GardenShapeView: View {
    let category: GardenShapeCategory
    let variation: Int
    let color: Color

    var body: some View {
        if category == .empty {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 3, height: 3)
        } else {
            Image(systemName: symbolID)
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                // Use a thin weight to mimic hand-drawn outlines
                .font(.system(size: 16, weight: .light, design: .rounded))
        }
    }

    private var symbolID: String {
        switch category {
        case .empty:
            return ""
        case .sprout: // Spark
            let symbols = ["sparkle", "smallcircle.filled.circle", "light.min"]
            return symbols[variation % symbols.count]
        case .leaf: // Star
            let symbols = ["star", "moonphase.waxing.crescent", "star.fill"]
            return symbols[variation % symbols.count]
        case .flower: // Moon
            let symbols = ["moon", "moon.stars", "moon.circle"]
            return symbols[variation % symbols.count]
        case .tree: // Constellation / Galaxy
            let symbols = ["sparkles", "sun.max", "sun.dust.fill"]
            return symbols[variation % symbols.count]
        }
    }
}
