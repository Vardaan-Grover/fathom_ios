import SwiftUI
import UIKit

/// A book, pre-resolved for a share card. The cover is a concrete `UIImage`
/// (loaded synchronously) because `ImageRenderer` can't wait on `AsyncImage`.
struct ShareBook {
    let title: String
    let author: String?
    let cover: UIImage?
}

/// The single-doodle share card: one earned doodle, glowing dead-center, named
/// in a hand, with the date — and optionally the book that time came from.
/// No `@Environment` (rendered via `ImageRenderer`); colors come from `theme`.
struct DoodleShareCardView: View {
    let doodleName: String
    let phrase: String        // "a comet"
    let date: Date
    let name: String
    let book: ShareBook?      // nil → not included
    let theme: ShareCardTheme
    let format: ShareCardFormat

    private var story: Bool { format == .story }

    var body: some View {
        VStack(spacing: 0) {
            if !name.isEmpty {
                Text("\(name.uppercased())’S SKY")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(theme.secondary)
                    .padding(.top, story ? 46 : 34)
            }

            Spacer(minLength: 0)

            // Hero group, centered as one block.
            VStack(spacing: story ? 8 : 6) {
                medallion

                Text("you spotted")
                    .font(.system(size: 17, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(theme.secondary)
                Text(phrase)
                    .font(.custom("Reenie Beanie", size: story ? 58 : 52))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                Text(dateText)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .tracking(1.5)
                    .foregroundStyle(theme.secondary)
                    .padding(.top, 2)

                if let book {
                    bookRow(book).padding(.top, story ? 20 : 16)
                }
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            Text("made with Fathom ✦")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(theme.secondary)
                .padding(.bottom, story ? 46 : 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private var medallion: some View {
        ZStack {
            RadialGradient(colors: [theme.ink.opacity(0.2), .clear],
                           center: .center, startRadius: 2, endRadius: 118)
                .frame(width: 240, height: 200)
                .blur(radius: 16)
            Image(doodleName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(theme.ink)
                .frame(height: story ? 140 : 118)
                .shadow(color: theme.ink.opacity(0.25), radius: 9)
        }
    }

    /// A compact, centered chip — sized to its content so there's no dead space.
    private func bookRow(_ book: ShareBook) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover = book.cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    ZStack {
                        theme.ink.opacity(0.15)
                        Text(book.title.prefix(1))
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(theme.ink)
                    }
                }
            }
            .frame(width: 34, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 11, design: .serif)).italic()
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 190, alignment: .leading)
        }
        .fixedSize()
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.ink.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(theme.ink.opacity(0.12), lineWidth: 1))
        )
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date).uppercased()
    }
}

/// Preview + share for the single-doodle card, with a toggle for including the book.
struct DoodleSharePreviewSheet: View {
    let doodleName: String
    let phrase: String
    let date: Date
    let name: String
    let book: Book?
    let theme: ShareCardTheme

    @State private var includeBook = true

    /// Cover loaded synchronously from its local file (covers are on-disk), so it
    /// exists at render time.
    private var shareBook: ShareBook? {
        guard let book else { return nil }
        let cover = book.coverURL.flatMap { UIImage(contentsOfFile: $0.path) }
        return ShareBook(title: book.title, author: book.author, cover: cover)
    }

    var body: some View {
        ShareCardScaffold(
            title: "Share this night",
            formats: [.story, .square],
            ink: theme.ink,
            controls: {
                if book != nil {
                    Toggle(isOn: $includeBook) {
                        Text("Include the book you read")
                            .font(.system(size: 15, design: .serif))
                    }
                    .tint(theme.ink)
                    .padding(.horizontal, 4)
                }
            },
            card: { format in
                DoodleShareCardView(
                    doodleName: doodleName, phrase: phrase, date: date, name: name,
                    book: includeBook ? shareBook : nil, theme: theme, format: format)
            }
        )
    }
}
