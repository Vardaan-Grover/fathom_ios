import Foundation
import GRDB
import SwiftUI

struct Book: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "books"

    let id: UUID
    let title: String
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

    var estimatedPageCount: Int? = nil
    var estimatedReadingTimeMinutes: Int? = nil

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

enum ReaderTheme: String, Codable, CaseIterable {
    case light
    case sepia
    case dark
}

struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 1.0
    var lineHeight: Double = 1.4
    var theme: ReaderTheme = .light
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case blue
    case pink
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor.systemYellow.withAlphaComponent(0.4)
        case .green: return UIColor.systemGreen.withAlphaComponent(0.4)
        case .blue: return UIColor.systemBlue.withAlphaComponent(0.4)
        case .pink: return UIColor.systemPink.withAlphaComponent(0.4)
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
        }
    }
}

struct Highlight: Identifiable, Codable {
    let id: UUID
    let bookID: UUID
    let locatorJSON: String
    let text: String
    let createdAt: Date
    var color: HighlightColor
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
