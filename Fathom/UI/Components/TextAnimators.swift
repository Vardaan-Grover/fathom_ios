import SwiftUI

@available(iOS 18.0, *)
struct StreamingTextRenderer: TextRenderer, Animatable {
    var progress: Double  // 0.0 to 1.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    init(progress: Double) {
        self.progress = progress
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // Collect all slices to determine sequence
        var allSlices: [Text.Layout.RunSlice] = []
        for line in layout {
            for run in line {
                for slice in run {
                    allSlices.append(slice)
                }
            }
        }

        let totalCount = max(Double(allSlices.count), 1.0)
        let currentTargetIndex = progress * (totalCount + 3.0)

        for (index, slice) in allSlices.enumerated() {
            var copy = ctx
            let sliceDoubleIndex = Double(index)

            if sliceDoubleIndex <= currentTargetIndex {
                // Determine how close we are to the leading edge (the cursor)
                let distanceToEdge = currentTargetIndex - sliceDoubleIndex

                if distanceToEdge < 3.0 {  // Affect the latest 3 slices
                    let intensity = 1.0 - (distanceToEdge / 3.0)

                    // Pop up slightly
                    copy.translateBy(x: 0, y: -sin(intensity * .pi) * 3.0)
                    // Slight glow or opacity bump
                    copy.opacity = 1.0
                } else {
                    copy.opacity = 1.0
                }

                copy.draw(slice)
            } else {
                // Not yet revealed
                copy.opacity = 0.0
                copy.draw(slice)
            }
        }
    }
}
