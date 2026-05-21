import Foundation
import GRDB
import SwiftUI

struct Book: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "books"

    let id: UUID
    var title: String
    var author: String?
    var format: BookFormat
    var localFilename: String?

    var description: String?
    var language: String?
    var publisher: String?
    var coverFilename: String?

    var importDate: Date = Date()
    var preprocessingStatus: PreprocessingStatus = .pending
    var aiAnalysisProgress: Float = 0.0
    var aiEnabled: Bool = false
    var backendBookID: UUID? = nil
    var contentHash: String? = nil

    var estimatedPageCount: Int? = nil
    var estimatedReadingTimeMinutes: Int? = nil
    var lastReadAt: Date? = nil

    var localURL: URL? {
        guard let filename = localFilename else { return nil }
        guard
            let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: false)
        else { return nil }
        return appSupport.appendingPathComponent("Books").appendingPathComponent(filename)
    }

    var coverURL: URL? {
        guard let filename = coverFilename else { return nil }
        return BookFileStore.coverURL(for: filename)
    }
}

enum BookFormat: String, Codable {
    case epub
    case pdf
}

struct BookCategory: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookCategories"
    let id: UUID
    var name: String
    var shelfColorHex: String
    var createdAt: Date
    var sortOrder: Int = 0
    var modifiedAt: Date = Date()
}

struct BookCategoryMembership: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookCategoryMemberships"
    let bookID: UUID
    let categoryID: UUID
    let addedAt: Date
    var sortOrder: Int = 0
    var modifiedAt: Date = Date()
}

struct Passage: Identifiable, Equatable {
    let id: UUID
    let bookID: UUID
    let chapterTitle: String?
    let selectedText: String
    let beforeText: String
    let afterText: String
}

struct ContextBundle: Equatable {
    let bookID: UUID
    let selectedText: String
    let localWindow: String
    let chapterTitle: String?
    let readingPositionHint: String?
}

struct Explanation: Equatable {
    let output: String
    let model: String
    let cached: Bool
}

enum ReaderColorTheme: Int, Codable, CaseIterable {
    case parchment = 0
    case night     = 1
    case paper     = 2
    case stone     = 3
    case ebony     = 4
    case espresso  = 5
}

enum ReaderFont: String, Codable, CaseIterable {
    case original
    case newYork
    case georgia
    case palatino
    case iowanOldStyle
    case charter
    case sfProText
    case avenir
}

enum ReadingLayout: String, Codable {
    case paginated
    case scrolling
}

struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 1.0
    var lineHeight: Double = 1.4
    var colorTheme: ReaderColorTheme = .paper
    var font: ReaderFont = .original
    var margin: Double = 1.5
    var justifyText: Bool = false
    var layout: ReadingLayout = .paginated
    var boldText: Bool = false
}

extension ReaderColorTheme {
    var backgroundHex: String {
        switch self {
        case .parchment: "f1e1c9"
        case .night:     "1b1b1d"
        case .paper:     "fefbf3"
        case .stone:     "eeecec"
        case .ebony:     "18160c"
        case .espresso:  "423b30"
        }
    }

    var foregroundHex: String {
        switch self {
        case .parchment: "34281d"
        case .night:     "f2f2f0"
        case .paper:     "141200"
        case .stone:     "1e1a1a"
        case .ebony:     "fff9ea"
        case .espresso:  "f9ebdb"
        }
    }

    var backgroundColor: Color { Color(hex: backgroundHex) }
    var foregroundColor: Color { Color(hex: foregroundHex) }

    var isDark: Bool {
        switch self {
        case .night, .ebony, .espresso: true
        default: false
        }
    }

    var dimColor: Color {
        isDark ? .black.opacity(0.45) : .black.opacity(0.35)
    }

    var displayName: String {
        switch self {
        case .parchment: "Parchment"
        case .night:     "Night"
        case .paper:     "Paper"
        case .stone:     "Stone"
        case .ebony:     "Ebony"
        case .espresso:  "Espresso"
        }
    }

    func next() -> ReaderColorTheme {
        let all = ReaderColorTheme.allCases
        let idx = (rawValue + 1) % all.count
        return all[idx]
    }
}

extension ReaderFont {
    var displayName: String {
        switch self {
        case .original:      "Original"
        case .newYork:       "New York"
        case .georgia:       "Georgia"
        case .palatino:      "Palatino"
        case .iowanOldStyle: "Iowan Old Style"
        case .charter:       "Charter"
        case .sfProText:     "SF Pro Text"
        case .avenir:        "Avenir"
        }
    }

    /// The CSS font-family name to pass to Readium. `nil` means use publisher font.
    var cssFamily: String? {
        switch self {
        case .original:      nil
        case .newYork:       "New York"
        case .georgia:       "Georgia"
        case .palatino:      "Palatino"
        case .iowanOldStyle: "Iowan Old Style"
        case .charter:       "Charter"
        case .sfProText:     "-apple-system"
        case .avenir:        "Avenir"
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case blue
    case pink
    case indigo
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.00, green: 0.90, blue: 0.30, alpha: 1.0)
        case .green:  return UIColor(red: 0.45, green: 0.90, blue: 0.55, alpha: 1.0)
        case .blue:   return UIColor(red: 0.45, green: 0.75, blue: 1.00, alpha: 1.0)
        case .pink:   return UIColor(red: 1.00, green: 0.60, blue: 0.75, alpha: 1.0)
        case .indigo: return UIColor(red: 0.65, green: 0.60, blue: 1.00, alpha: 1.0)
        }
    }
}

extension HighlightColor {
    var displayColor: Color {
        switch self {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .indigo: return Color(.systemIndigo)
        }
    }

    /// Colors available for plain text highlights (excludes note-only indigo).
    static var highlightCases: [HighlightColor] { [.yellow, .green, .blue, .pink] }
}

struct Highlight: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "highlights"

    let id: UUID
    let bookID: UUID
    let locatorJSON: String
    let text: String
    let createdAt: Date
    var color: HighlightColor
}

struct Note: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    let id: UUID
    let bookID: UUID
    let locatorJSON: String
    let selectedText: String
    var noteContent: String
    let createdAt: Date
    var chapterTitle: String?
    var pageNumber: Int?
    var highlightColor: HighlightColor

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: String,
        selectedText: String,
        noteContent: String = "",
        createdAt: Date = Date(),
        chapterTitle: String? = nil,
        pageNumber: Int? = nil,
        highlightColor: HighlightColor = .indigo
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.selectedText = selectedText
        self.noteContent = noteContent
        self.createdAt = createdAt
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
        self.highlightColor = highlightColor
    }
}

struct Bookmark: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookmarks"

    let id: UUID
    let bookID: UUID
    let locatorJSON: String
    let progression: Double
    var chapterTitle: String?
    var pageNumber: Int?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: String,
        progression: Double,
        chapterTitle: String? = nil,
        pageNumber: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.progression = progression
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
        self.createdAt = createdAt
    }
}

enum AIMessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct AIMessage: Identifiable, Codable {
    let id: UUID
    let role: AIMessageRole
    let content: String
    let createdAt: Date
}

struct AIThread: Identifiable, Codable {
    let id: UUID
    let bookID: UUID
    let passageText: String
    let locatorJSON: String?
    let chapterTitle: String?
    let createdAt: Date
    var messages: [AIMessage]
}
