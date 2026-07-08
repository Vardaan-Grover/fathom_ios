import SwiftUI

/// Holds a card's last-known global frame outside of SwiftUI's state system,
/// so a GeometryReader can keep it up to date during scrolling without
/// triggering a re-render on every frame.
private final class CardFrameHolder {
    var rect: CGRect = .zero
}

struct VocabWordCard: View {
    let word: SavedWord
    let cardColor: Color
    let isAppeared: Bool
    let onExpand: (CGRect) -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void

    @Environment(\.appTheme) var theme
    // Plain reference holder (not @State) — the GeometryReader below updates this
    // directly on every layout pass without going through SwiftUI state, so
    // scrolling doesn't trigger a re-render of the card on every frame.
    @State private var frameHolder = CardFrameHolder()

    private var snippet: String { firstDefinitionSnippet(for: word) }

    var body: some View {
        Button {
            onExpand(frameHolder.rect)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(cardColor)

                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.black.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

                VStack(alignment: .leading, spacing: 6) {
                    posPill

                    Text(word.word)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(theme.typography.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    bookSource.padding(.top, 6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)

                if word.pinnedAt != nil {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(6)
                        .background(Circle().fill(.white.opacity(0.22)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(SpringPressStyle())
        .contextMenu {
            Button { onPin() } label: {
                Label(
                    word.pinnedAt != nil ? "Unpin" : "Pin",
                    systemImage: word.pinnedAt != nil ? "pin.slash" : "pin"
                )
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 40)
        .scaleEffect(isAppeared ? 1 : 0.92)
        .background(
            GeometryReader { geo -> Color in
                frameHolder.rect = geo.frame(in: .global)
                return Color.clear
            }
        )
    }

    private var posPill: some View {
        let pos = word.partsOfSpeech.components(separatedBy: ", ").first ?? word.partsOfSpeech
        return Text(pos.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.24)))
    }

    @ViewBuilder
    private var bookSource: some View {
        if let title = word.bookTitle {
            HStack(spacing: 4) {
                Image(systemName: "book.closed").font(.system(size: 9))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}
