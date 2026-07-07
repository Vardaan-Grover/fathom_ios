import SwiftUI
import Combine

struct DailyActivity: Identifiable, Equatable {
    let id: String // Date string "YYYY-MM-DD"
    let date: Date
    let duration: TimeInterval
    let bookIDs: [UUID]
    /// Minutes-read per book on this day, so the detail sheet can show a
    /// breakdown (and order the major book ahead of the minor ones).
    var bookDurations: [UUID: TimeInterval] = [:]
}

@MainActor
final class MemoryGardenViewModel: ObservableObject {
    @Published var dailyActivities: [String: DailyActivity] = [:]
    @Published var isLoading = true
    @Published var loadedBooks: [UUID: Book] = [:]
    
    private let bookRepository: BookRepository
    
    init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }
    
    func load(forYear year: Int) async {
        isLoading = true
        let rawActivities = await bookRepository.listReadingActivity(forYear: year)
        
        var aggregated: [String: DailyActivity] = [:]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        
        for activity in rawActivities {
            guard let date = formatter.date(from: activity.date) else { continue }
            
            if let existing = aggregated[activity.date] {
                var newIDs = existing.bookIDs
                if !newIDs.contains(activity.bookID) {
                    newIDs.append(activity.bookID)
                }
                var perBook = existing.bookDurations
                perBook[activity.bookID, default: 0] += activity.duration
                aggregated[activity.date] = DailyActivity(
                    id: activity.date,
                    date: date,
                    duration: existing.duration + activity.duration,
                    bookIDs: newIDs,
                    bookDurations: perBook
                )
            } else {
                aggregated[activity.date] = DailyActivity(
                    id: activity.date,
                    date: date,
                    duration: activity.duration,
                    bookIDs: [activity.bookID],
                    bookDurations: [activity.bookID: activity.duration]
                )
            }
        }
        
        self.dailyActivities = aggregated
        
        // Also fetch the full list of books so we have their covers for the popover
        let allBooks = await bookRepository.listBooks()
        var booksDict: [UUID: Book] = [:]
        for book in allBooks {
            booksDict[book.id] = book
        }
        self.loadedBooks = booksDict
        
        isLoading = false
    }
    
    func injectMockData(year: Int) async {
        let allBooks = await bookRepository.listBooks()
        guard !allBooks.isEmpty else { return }

        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        // Let's generate activity for about 1/3 of the days
        for dayOffset in 0..<365 {
            if Double.random(in: 0...1) < 0.35 {
                if let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfYear) {
                    let dateStr = formatter.string(from: date)
                    let randomBook = allBooks.randomElement()!
                    let duration = TimeInterval(Int.random(in: 60...4000)) // 1 min to 66 mins

                    let activity = ReadingActivity(id: UUID(), bookID: randomBook.id, date: dateStr, duration: duration, createdAt: Date())
                    await bookRepository.insertMockReadingActivity(activity)
                }
            }
        }

        await load(forYear: year)
    }

    /// Dev-only: wipes the year's reading activity and the "last revealed" marker,
    /// so the home observatory returns to a clean slate (lets you test the
    /// spotting state without a pending doodle stealing precedence).
    func clearMockData(year: Int) async {
        await bookRepository.deleteAllReadingActivity(forYear: year)
        UserDefaults.standard.removeObject(forKey: ObservatoryViewModel.lastRevealedKey)
        dailyActivities = [:]
        await load(forYear: year)
        NotificationCenter.default.post(name: .fathomReadingSessionLogged, object: nil)
    }

    /// Generates a *random reader profile* each roll, then fills the year with a
    /// streak-based (Markov) walk so every tap previews a genuinely different
    /// pattern — sparse vs dense, streaky runs vs scattered days, seasonal ebbs,
    /// and a different tier mix. Resets in-memory state first.
    func injectDenseMockData(year: Int) async {
        let allBooks = await bookRepository.listBooks()
        guard !allBooks.isEmpty else { return }

        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        // Clear the year's mock activity from the store first — otherwise each
        // roll piles on top of the last and the grid saturates to a full year.
        await bookRepository.deleteAllReadingActivity(forYear: year)
        self.dailyActivities = [:]

        // ── This roll's random reader profile ──────────────────────────────
        // startChance: how readily an idle day kicks off reading (drives overall fill).
        // continueChance: how "sticky" a reading streak is (drives consistency/run length).
        // Together these range from "a few scattered days" to "a packed, consistent year".
        let startChance = Double.random(in: 0.03...0.5)
        let continueChance = Double.random(in: 0.45...0.95)
        // Seasonal ebb & flow so activity isn't uniform across the year.
        let seasonAmp = Double.random(in: 0...0.7)
        let seasonPhase = Double.random(in: 0...(2 * .pi))
        let seasonHumps = Double(Int.random(in: 1...3))

        // Duration ranges per tier (seconds): glimpse <20 min, settledIn 20–45, grandNight 45+.
        let tierRanges: [ClosedRange<Int>] = [60...1100, 1200...2600, 2700...5400]
        // Random tier mix for this roll (tier-3 kept lighter — its art is large/sprawling).
        var tierWeights = [
            Double.random(in: 0.25...0.7),
            Double.random(in: 0.2...0.6),
            Double.random(in: 0.0...0.3),
        ]
        let weightSum = tierWeights.reduce(0, +)
        tierWeights = tierWeights.map { $0 / weightSum }

        // How far into the year "today" is. Half the time the year is complete;
        // otherwise we stop partway (e.g. ~40% ≈ it's only May) and leave the
        // rest of the grid as empty future days.
        let yearProgress = Double.random(in: 0...1) < 0.5 ? 1.0 : Double.random(in: 0.3...0.9)
        let lastDay = Int(365 * yearProgress)

        var isReading = false
        var streakBook = allBooks.randomElement()!

        for dayOffset in 0..<lastDay {
            let t = Double(dayOffset) / 365.0
            let season = 1 + seasonAmp * sin(seasonHumps * 2 * .pi * t + seasonPhase)
            let p = isReading ? continueChance : startChance * season
            let wasReading = isReading
            isReading = Double.random(in: 0...1) < min(0.98, max(0, p))
            guard isReading else { continue }
            // A new streak tends to start a new book; within a streak, stick with it.
            if !wasReading { streakBook = allBooks.randomElement()! }

            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfYear) else { continue }
            let dateStr = formatter.string(from: date)

            var cumulative = 0.0
            var range = tierRanges[0]
            let roll = Double.random(in: 0...1)
            for (i, w) in tierWeights.enumerated() {
                cumulative += w
                if roll <= cumulative { range = tierRanges[i]; break }
            }

            let activity = ReadingActivity(
                id: UUID(), bookID: streakBook.id, date: dateStr,
                duration: TimeInterval(Int.random(in: range)), createdAt: Date()
            )
            await bookRepository.insertMockReadingActivity(activity)
        }

        await load(forYear: year)
    }
}
