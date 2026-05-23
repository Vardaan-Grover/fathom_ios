import SwiftUI

// MARK: - BookCompletionPreviewCard
//
// Compact card shown on the Book Details screen when a book has been marked
// finished. Displays the dot rating and a truncated first line of the
// reflection. Tapping it re-opens BookCompletionScreen in edit mode.

struct BookCompletionPreviewCard: View {

    let book: Book
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    private var accent: Color { theme.colors.shelfAccent }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                
                if let url = book.reflectionImageURL, let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: theme.layout.cornerRadiusMedium))
                        .clipped()
                }
                
                if let reflection = book.reflection, !reflection.isEmpty {
                    reflectionPreview(reflection)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge)
                    .strokeBorder(accent.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(SpringPressStyle())
    }

    // MARK: - Header row: "Finished · date" + rating dots

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Finished", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                    .symbolRenderingMode(.hierarchical)

                if let date = book.finishedAt {
                    Text(date, format: .dateTime.month(.wide).day().year())
                        .font(theme.typography.caption)
                        .foregroundColor(theme.colors.secondary)
                }
            }

            Spacer()

            ratingDots
        }
    }

    // MARK: - Rating dots (read-only display)

    @ViewBuilder
    private var ratingDots: some View {
        if let rating = book.rating {
            let colors: [Color] = [
                Color(hex: "F38BA8"), // Pink
                Color(hex: "FAB387"), // Orange
                Color(hex: "89B4FA"), // Blue
                Color(hex: "94E2D5"), // Teal
                Color(hex: "A6E3A1")  // Green
            ]
            
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { i in
                    let color = colors[i - 1]
                    let isSelected = i == rating
                    
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.2))
                        .frame(width: 9, height: 9)
                }
            }
        }
    }

    // MARK: - Truncated reflection

    private func reflectionPreview(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.body)
            .foregroundColor(theme.colors.primary)
            .lineLimit(2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
