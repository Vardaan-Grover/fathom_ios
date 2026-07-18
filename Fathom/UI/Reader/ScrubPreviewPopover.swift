import ReadiumShared
import SwiftUI

/// Chapter + page readout shown above the progress scrubber while dragging.
struct ScrubPreviewPopover: View {
    let progression: Double
    let positionIndex: BookPositionIndex
    let foregroundColor: SwiftUI.Color
    let backgroundColor: SwiftUI.Color

    var body: some View {
        if let locator = positionIndex.locator(atTotalProgression: progression) {
            let chapterTitle = positionIndex.chapterTitle(atTotalProgression: progression)
                ?? locator.title

            VStack(spacing: 6) {
                if let title = chapterTitle, !title.isEmpty {
                    Text(title.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(foregroundColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if let position = locator.locations.position {
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
