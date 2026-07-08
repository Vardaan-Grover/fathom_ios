import ReadiumShared
import SwiftUI

/// Chapter + page readout shown above the progress scrubber while dragging.
struct ScrubPreviewPopover: View {
    let progression: Double
    let positions: [Locator]
    let tableOfContents: [ReadiumShared.Link]
    let foregroundColor: SwiftUI.Color
    let backgroundColor: SwiftUI.Color

    private var projectedLocator: Locator? {
        guard !positions.isEmpty else { return nil }
        let index = max(0, min(Int(progression * Double(positions.count - 1)), positions.count - 1))
        return positions[index]
    }

    private var chapterTitle: String? {
        guard !positions.isEmpty else { return nil }
        return tocChapterTitle(
            atTotalProgression: progression,
            positions: positions,
            tableOfContents: tableOfContents
        ) ?? projectedLocator?.title
    }

    var body: some View {
        if let locator = projectedLocator {
            VStack(spacing: 6) {
                if let title = chapterTitle, !title.isEmpty {
                    Text(title.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(foregroundColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if let position = locator.locations.position, positions.count > 0 {
                    Text("Page \(position)")
                        .font(.body)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                } else {
                    Text("\(Int(progression * 100))%")
                        .font(.body)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            EmptyView()
        }
    }
}
