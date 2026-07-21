import SwiftUI

// MARK: - EmojiGridPicker
//
// A first-party emoji picker: category strip on top, tappable grid below.
//
// This replaces an earlier trick that mounted an invisible UITextField and
// overrode `textInputMode` to force the system emoji keyboard open. That
// relied on `UITextInputMode.activeInputModes`, which Apple classifies as a
// Required Reason API — and neither approved reason fits Fathom (3EC4.1 is
// for custom keyboard apps, 54BD.1 is for displaying the keyboard list to the
// user). Picking from our own grid removes the API from the binary entirely,
// and takes the focus-nudge plumbing with it.

struct EmojiGridPicker: View {
    /// The chosen emoji. Empty string means nothing is selected.
    @Binding var selection: String

    @Environment(\.appTheme) private var theme
    @State private var activeCategoryID: String = EmojiCatalog.categories[0].id

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var activeCategory: EmojiCatalog.Category {
        EmojiCatalog.categories.first { $0.id == activeCategoryID }
            ?? EmojiCatalog.categories[0]
    }

    var body: some View {
        VStack(spacing: 10) {
            categoryStrip

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(activeCategory.emoji, id: \.self) { emoji in
                        EmojiCell(
                            emoji: emoji,
                            isSelected: emoji == selection
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selection = emoji
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            // Grid scrolls within itself. Callers place this in a plain VStack
            // rather than a ScrollView so the two don't fight over the gesture.
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Category strip

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(EmojiCatalog.categories) { category in
                    let isActive = category.id == activeCategoryID
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        activeCategoryID = category.id
                    } label: {
                        Text(category.tabEmoji)
                            .font(.system(size: 19))
                            .frame(width: 40, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isActive
                                          ? theme.colors.primary.opacity(0.12)
                                          : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isActive
                                        ? theme.colors.primary.opacity(0.35)
                                        : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.name)
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: activeCategoryID)
    }
}

// MARK: - EmojiCell

private struct EmojiCell: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? theme.colors.primary.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? theme.colors.primary.opacity(0.5) : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .scaleEffect(isSelected ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(emoji)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - EmojiCatalog

/// Curated rather than exhaustive. These sets are for avatars and shelf
/// stickers, so they lean toward the app's own register — cozy, celestial,
/// bookish — instead of dumping every Unicode block on the user.
enum EmojiCatalog {

    struct Category: Identifiable, Hashable {
        let id: String
        let tabEmoji: String
        let emoji: [String]
        var name: String { id }
    }

    static let categories: [Category] = [
        Category(id: "Night", tabEmoji: "🌙", emoji: [
            "🌙", "⭐️", "✨", "🌟", "💫", "☄️", "🌌", "🪐", "🔭", "🌠",
            "🌕", "🌖", "🌗", "🌘", "🌑", "🌒", "🌓", "🌔", "🌛", "🌜",
            "🌚", "🌝", "🕯️", "🔮", "🧿", "🪬", "🗝️", "🕰️", "⏳", "🪄",
        ]),
        Category(id: "Cozy", tabEmoji: "☕", emoji: [
            "☕", "🍵", "🫖", "📖", "📚", "🔖", "📝", "🖋️", "📜", "✒️",
            "🧣", "🧦", "🛋️", "🛌", "💤", "🧸", "🎀", "🪴", "🧶", "🧵",
            "🎧", "🎵", "🎶", "📻", "🖼️", "🪞", "🔥", "🪵", "🌧️", "☔️",
        ]),
        Category(id: "Nature", tabEmoji: "🌿", emoji: [
            "🌿", "🍀", "☘️", "🌱", "🌲", "🌳", "🌴", "🌵", "🎋", "🍃",
            "🍂", "🍁", "🍄", "🌾", "💐", "🌷", "🌹", "🌺", "🌸", "🌼",
            "🌻", "🌊", "🐚", "🪸", "❄️", "☃️", "🌈", "☀️", "⛅️", "🌪️",
        ]),
        Category(id: "Animals", tabEmoji: "🦊", emoji: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
            "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦆", "🦉",
            "🦇", "🐺", "🐴", "🦄", "🐝", "🦋", "🐌", "🐞", "🐢", "🐙",
            "🐳", "🐬", "🐠", "🦕", "🦖", "🦥", "🦦", "🐈", "🐕", "🕊️",
        ]),
        Category(id: "Food", tabEmoji: "🍓", emoji: [
            "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒",
            "🍑", "🥭", "🍍", "🥥", "🥝", "🥑", "🥐", "🥖", "🥨", "🧀",
            "🍕", "🍔", "🍟", "🌮", "🍜", "🍣", "🍱", "🥟", "🍚", "🍡",
            "🍦", "🍰", "🧁", "🍩", "🍪", "🍫", "🍬", "🍭", "🍿", "🍯",
        ]),
        Category(id: "Places", tabEmoji: "🏝️", emoji: [
            "🏝️", "🏖️", "🏜️", "🏔️", "⛰️", "🌋", "🏕️", "⛺️", "🏰", "🏯",
            "🗼", "🗽", "⛩️", "🎡", "🎢", "🗺️", "🧭", "⚓️", "⛵️", "🚢",
            "✈️", "🚀", "🛸", "🎈", "🚂", "🚲", "🛵", "🗿", "🌉", "🎑",
        ]),
        Category(id: "Play", tabEmoji: "🎨", emoji: [
            "🎨", "🖌️", "🖍️", "🎭", "🎬", "🎤", "🎼", "🎹", "🥁", "🎷",
            "🎺", "🎸", "🪕", "🎻", "📷", "📼", "🕹️", "👾", "♟️", "🎲",
            "🧩", "🎯", "🏆", "⚽️", "🏀", "🎾", "🛹", "⛸️", "🎿", "🧘",
        ]),
        Category(id: "Hearts", tabEmoji: "❤️", emoji: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💖",
            "💗", "💓", "💞", "💕", "💝", "💘", "❣️", "💌", "👑", "💎",
            "🎁", "🎉", "🎊", "🪩", "⚡️", "🔥", "💧", "🌀", "☮️", "♾️",
        ]),
    ]
}
