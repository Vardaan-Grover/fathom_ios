import Foundation
import GRDB

// MARK: - DataExporter
//
// Builds a JSON archive of the user's library + annotations + vocabulary,
// suitable for sharing via the system Share Sheet.

enum DataExporterError: LocalizedError {
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let e): return "Failed to write export file: \(e.localizedDescription)"
        }
    }
}

struct ExportedArchive: Codable {
    let exportedAt: Date
    let appVersion: String
    let books: [ExportedBook]
    let highlights: [Highlight]
    let notes: [Note]
    let bookmarks: [Bookmark]
    let vocabulary: [ExportedSavedWord]
}

struct ExportedBook: Codable {
    let id: UUID
    let title: String
    let author: String?
    let language: String?
    let publisher: String?
    let importDate: Date
    let lastReadAt: Date?
    let aiEnabled: Bool
}

/// A minimal version of `SavedWord` for export — strips the raw dictionary
/// blob to keep file size manageable.
struct ExportedSavedWord: Codable {
    let word: String
    let language: String
    let partsOfSpeech: String
    let bookTitle: String?
    let chapter: String?
    let pageNumber: Int?
    let contextSentence: String?
    let createdAt: Date
    let pinnedAt: Date?
}

enum DataExporter {

    /// Generates the JSON archive and writes it to a temp file. Returns the URL.
    /// The caller is responsible for showing the share sheet.
    static func export() async throws -> URL {
        let archive = try await buildArchive()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(archive)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: Date())

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fathom-Export-\(dateStr).json")

        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            throw DataExporterError.writeFailed(underlying: error)
        }
    }

    // MARK: - Build

    private static func buildArchive() async throws -> ExportedArchive {
        let books = try await DatabaseManager.shared.dbQueue.read { db in
            try Book.fetchAll(db)
        }
        let highlights = HighlightStore.shared.allHighlights()
        let notes = NoteStore.shared.allNotes()
        let bookmarks = BookmarkStore.shared.allBookmarks()

        let saved = try await DatabaseManager.shared.dbQueue.read { db in
            try SavedWord
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }

        let exportedBooks = books.map {
            ExportedBook(
                id: $0.id,
                title: $0.title,
                author: $0.author,
                language: $0.language,
                publisher: $0.publisher,
                importDate: $0.importDate,
                lastReadAt: $0.lastReadAt,
                aiEnabled: $0.aiEnabled
            )
        }

        let exportedVocab = saved.map {
            ExportedSavedWord(
                word: $0.word,
                language: $0.language,
                partsOfSpeech: $0.partsOfSpeech,
                bookTitle: $0.bookTitle,
                chapter: $0.chapter,
                pageNumber: $0.pageNumber,
                contextSentence: $0.contextSentence,
                createdAt: $0.createdAt,
                pinnedAt: $0.pinnedAt
            )
        }

        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "unknown"

        return ExportedArchive(
            exportedAt: Date(),
            appVersion: appVersion,
            books: exportedBooks,
            highlights: highlights,
            notes: notes,
            bookmarks: bookmarks,
            vocabulary: exportedVocab
        )
    }
}
