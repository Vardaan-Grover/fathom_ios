import SwiftUI
import UIKit

/// Reading stats for a finished book, resolved for its share card.
struct BookShareStats {
    let hours: String
    let nights: Int
    /// The doodles earned on the nights this book was read (its "constellation").
    let doodles: [String]
}

/// The book-finished share card — a milestone. The cover is the hero, with the
/// little constellation of doodles you earned while reading it beneath.
struct BookShareCardView: View {
    let title: String
    let author: String?
    let cover: UIImage?
    let rating: Int
    let finishedDate: Date
    let name: String
    let line: String
    let stats: BookShareStats?
    let theme: ShareCardTheme
    let format: ShareCardFormat

    private var story: Bool { format == .story }

    var body: some View {
        VStack(spacing: 0) {
            Text(name.isEmpty ? "A BOOK, FINISHED" : "\(name.uppercased())’S SKY")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .tracking(2)
                .foregroundStyle(theme.secondary)
                .padding(.top, story ? 46 : 32)

            Spacer(minLength: 0)

            bookCover
                .padding(.bottom, 18)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: story ? 27 : 23, weight: .bold, design: .serif))
                    .foregroundStyle(theme.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 14, design: .serif)).italic()
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 34)

            if rating > 0 {
                stars.padding(.top, 12)
            }

            Text("FINISHED \(finishedText)")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .tracking(1.5)
                .foregroundStyle(theme.secondary)
                .padding(.top, 12)

            if let stats, !stats.doodles.isEmpty {
                constellation(stats.doodles).padding(.top, 20)
                Text("READ ACROSS \(stats.nights) \(stats.nights == 1 ? "NIGHT" : "NIGHTS") · \(stats.hours) HOURS")
                    .font(.system(size: 9.5, weight: .semibold, design: .serif))
                    .tracking(1)
                    .foregroundStyle(theme.secondary)
                    .padding(.top, 10)
            }

            if !line.isEmpty {
                Text(line)
                    .font(.custom("Reenie Beanie", size: 30))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 34)
            }

            Spacer(minLength: 0)

            Text("made with Fathom ✦")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(theme.secondary)
                .padding(.bottom, story ? 44 : 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    // MARK: Cover hero

    private var bookCover: some View {
        let w: CGFloat = story ? 150 : 128
        let h: CGFloat = w * 1.44
        return ZStack {
            // A soft glow so the cover sits in a little pool of light.
            RadialGradient(colors: [theme.ink.opacity(0.22), .clear],
                           center: .center, startRadius: 4, endRadius: w * 1.3)
                .frame(width: w * 2.4, height: h * 1.5)
                .blur(radius: 24)

            coverImage
                .frame(width: w, height: h)
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [.black.opacity(0.3), .clear],
                                   startPoint: .leading, endPoint: .trailing).frame(width: 6)
                }
                .overlay(alignment: .trailing) {
                    LinearGradient(colors: [.clear, .white.opacity(0.5)],
                                   startPoint: .leading, endPoint: .trailing).frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.black.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.38), radius: 18, x: 2, y: 12)
        }
    }

    @ViewBuilder private var coverImage: some View {
        if let cover {
            Image(uiImage: cover).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [theme.ink.opacity(0.85), theme.ink.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(title.prefix(1))
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }

    private var stars: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(i <= rating ? theme.ink : theme.secondary.opacity(0.4))
            }
        }
    }

    private func constellation(_ doodles: [String]) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(doodles.prefix(9).enumerated()), id: \.offset) { _, name in
                Image(name)
                    .renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(theme.ink)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 24)
    }

    private var finishedText: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: finishedDate).uppercased()
    }
}

/// Preview + share for the book-finished card. Loads the book's reading stats +
/// doodle constellation asynchronously.
struct BookSharePreviewSheet: View {
    let book: Book
    let bookRepository: BookRepository
    let rating: Int
    let finishedDate: Date
    let name: String
    let theme: ShareCardTheme

    @State private var line: String
    @State private var stats: BookShareStats?
    @State private var coverImage: UIImage?
    @FocusState private var focused: Bool

    init(book: Book, bookRepository: BookRepository, rating: Int, finishedDate: Date,
         name: String, theme: ShareCardTheme) {
        self.book = book
        self.bookRepository = bookRepository
        self.rating = rating
        self.finishedDate = finishedDate
        self.name = name
        self.theme = theme
        _line = State(initialValue: "a book kept in the stars")
        _coverImage = State(initialValue: book.coverURL.flatMap { UIImage(contentsOfFile: $0.path) })
    }

    var body: some View {
        ShareCardScaffold(
            title: "Share this finish",
            formats: [.story, .square],
            ink: theme.ink,
            controls: {
                TextField("a book kept in the stars", text: $line)
                    .font(.system(size: 16, design: .serif))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .onChange(of: line) { _, new in
                        if new.contains("\n") { line = new.replacingOccurrences(of: "\n", with: "") }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            },
            card: { format in
                BookShareCardView(
                    title: book.title, author: book.author, cover: coverImage,
                    rating: rating, finishedDate: finishedDate, name: name, line: line,
                    stats: stats, theme: theme, format: format)
            }
        )
        .task { stats = await loadStats() }
    }

    private func loadStats() async -> BookShareStats {
        let cal = Calendar.current
        let year = cal.component(.year, from: finishedDate)
        var all = await bookRepository.listReadingActivity(forYear: year)
        all += await bookRepository.listReadingActivity(forYear: year - 1)   // span a year boundary

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let todayStart = cal.startOfDay(for: Date())

        var dayTotal: [String: TimeInterval] = [:]
        var bookDays: [String: TimeInterval] = [:]
        for a in all {
            dayTotal[a.date, default: 0] += a.duration
            if a.bookID == book.id { bookDays[a.date, default: 0] += a.duration }
        }
        let nights = bookDays.keys.count
        let seconds = bookDays.values.reduce(0, +)
        let doodles = bookDays.keys.sorted().compactMap { d -> String? in
            guard let date = fmt.date(from: d), date < todayStart else { return nil }
            let doy = cal.ordinality(of: .day, in: .year, for: date) ?? 1
            return DoodleCatalog.assetName(forDayOfYear: doy, duration: dayTotal[d] ?? 0)
        }
        let h = seconds / 3600
        return BookShareStats(hours: h >= 1 ? String(Int(h.rounded())) : "<1",
                              nights: nights, doodles: doodles)
    }
}
