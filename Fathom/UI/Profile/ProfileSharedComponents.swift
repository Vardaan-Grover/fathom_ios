import SwiftUI
import Combine
import GRDB

// MARK: - Shared components used by the All Notes / Highlights / Bookmarks screens

// MARK: - BookDirectory
//
// In-memory map of `bookID -> Book` for fast cover/title lookups across the
// All* screens. Reloaded whenever a screen appears so library edits are
// reflected.

@MainActor
final class BookDirectory: ObservableObject {
    @Published private(set) var byID: [UUID: Book] = [:]

    func reload() {
        do {
            let books = try DatabaseManager.shared.dbQueue.read { db in
                try Book.fetchAll(db)
            }
            byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        } catch {
            AppLogger.log(tag: "BookDirectory", "Failed to load: \(error)")
        }
    }

    var allBooks: [Book] {
        byID.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - MiniBookCover
//
// Compact book cover used on cross-book list cards.

struct MiniBookCover: View {
    let book: Book?
    var width: CGFloat = 32
    var height: CGFloat = 44

    var body: some View {
        ZStack {
            if let url = book?.coverURL, FileManager.default.fileExists(atPath: url.path) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray3), Color(.systemGray)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "book.closed.fill")
                .font(.system(size: width * 0.45))
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let symbol: String?
    let accent: Color?
    let isSelected: Bool
    let action: () -> Void

    init(
        label: String,
        symbol: String? = nil,
        accent: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.symbol = symbol
        self.accent = accent
        self.isSelected = isSelected
        self.action = action
    }

    private var chipAccent: Color { accent ?? Color.accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let accent, symbol == nil {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? chipAccent.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? chipAccent.opacity(0.5) : Color(.opaqueSeparator).opacity(0.7),
                                lineWidth: 1
                            )
                    )
            )
        }
        .foregroundStyle(isSelected ? chipAccent : Color.secondary)
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - Open-in-reader helper

enum ProfileBookOpener {
    /// Switches to the library tab and opens the given book at the locator.
    /// Piggybacks on the existing `.vocabularyJumpToBook` notification flow
    /// already wired in RootView.
    static func open(bookID: UUID, locatorJSON: String?) {
        NotificationCenter.default.post(
            name: .vocabularyJumpToBook,
            object: nil,
            userInfo: [
                "bookID": bookID,
                "locatorJSON": locatorJSON as Any
            ]
        )
    }
}

// MARK: - Empty state

struct CrossBookEmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var accent: Color = .accentColor

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
