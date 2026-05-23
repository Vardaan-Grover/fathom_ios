import SwiftUI
import Combine

struct DailyActivity: Identifiable, Equatable {
    let id: String // Date string "YYYY-MM-DD"
    let date: Date
    let duration: TimeInterval
    let bookIDs: [UUID]
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
                aggregated[activity.date] = DailyActivity(
                    id: activity.date,
                    date: date,
                    duration: existing.duration + activity.duration,
                    bookIDs: newIDs
                )
            } else {
                aggregated[activity.date] = DailyActivity(
                    id: activity.date,
                    date: date,
                    duration: activity.duration,
                    bookIDs: [activity.bookID]
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
}
