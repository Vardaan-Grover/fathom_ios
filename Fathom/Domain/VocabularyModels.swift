import Foundation
import GRDB

public struct DictionaryWordEntry: Codable, Equatable {
    public let word: String
    public let entries: [DictionaryEntry]
    public let source: DictionarySource?
}

public struct DictionaryEntry: Codable, Equatable {
    public let language: DictionaryLanguage
    public let partOfSpeech: String
    public let pronunciations: [DictionaryPronunciation]?
    public let forms: [DictionaryForm]?
    public let senses: [DictionarySense]
    public let synonyms: [String]?
    public let antonyms: [String]?
}

public struct DictionaryLanguage: Codable, Equatable {
    public let code: String
    public let name: String
}

public struct DictionaryPronunciation: Codable, Equatable {
    public let type: String?
    public let text: String?
    public let tags: [String]?
}

public struct DictionaryForm: Codable, Equatable {
    public let word: String
    public let tags: [String]?
}

public struct DictionarySense: Codable, Equatable {
    public let definition: String
    public let tags: [String]?
    public let examples: [String]?
    public let quotes: [DictionaryQuote]?
    public let synonyms: [String]?
    public let antonyms: [String]?
    public let translations: [DictionaryTranslation]?
    public let subsenses: [DictionarySense]?
}

public struct DictionaryQuote: Codable, Equatable {
    public let text: String
    public let reference: String?
}

public struct DictionaryTranslation: Codable, Equatable {
    public let language: DictionaryLanguage
    public let word: String
}

public struct DictionarySource: Codable, Equatable {
    public let url: String?
    public let license: DictionaryLicense?
}

public struct DictionaryLicense: Codable, Equatable {
    public let name: String
    public let url: String?
}

// MARK: - Local Database Models

public struct SavedWord: Identifiable, Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "saved_words"

    public let id: UUID
    public let word: String
    public let language: String
    public let partsOfSpeech: String  // Comma-separated for easier LIKE querying or full-text-search

    // Book association
    public let bookID: UUID?
    public let bookTitle: String?
    public let chapter: String?
    public let pageNumber: Int?
    public let locatorJSON: String?

    // Original sentence the user was reading
    public let contextSentence: String?

    // Raw dictionary response cached locally
    public let fullDictionaryJSON: Data?

    public let createdAt: Date

    // Non-nil when the word is pinned to the top; set to the pin timestamp
    public var pinnedAt: Date?
    /// Soft-delete tombstone — propagates the deletion to other devices via CloudKit.
    public var deletedAt: Date? = nil
    public var modifiedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        word: String,
        language: String,
        partsOfSpeech: String,
        bookID: UUID?,
        bookTitle: String?,
        chapter: String?,
        pageNumber: Int?,
        locatorJSON: String?,
        contextSentence: String?,
        fullDictionaryJSON: Data?,
        createdAt: Date = Date(),
        pinnedAt: Date? = nil,
        deletedAt: Date? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.language = language
        self.partsOfSpeech = partsOfSpeech
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.chapter = chapter
        self.pageNumber = pageNumber
        self.locatorJSON = locatorJSON
        self.contextSentence = contextSentence
        self.fullDictionaryJSON = fullDictionaryJSON
        self.createdAt = createdAt
        self.pinnedAt = pinnedAt
        self.deletedAt = deletedAt
        self.modifiedAt = modifiedAt
    }

    /// Helper to create a SavedWord from a DictionaryWordEntry API response
    public init(
        entry: DictionaryWordEntry,
        language: String,
        bookID: UUID?,
        bookTitle: String?,
        chapter: String?,
        pageNumber: Int?,
        locatorJSON: String?,
        contextSentence: String?
    ) {
        let uniquePartsOfSpeech = Set(entry.entries.map { $0.partOfSpeech })
        let partsOfSpeechStr = uniquePartsOfSpeech.sorted().joined(separator: ", ")

        let jsonData = try? JSONEncoder().encode(entry)

        self.init(
            id: UUID(),
            word: entry.word,
            language: language,
            partsOfSpeech: partsOfSpeechStr,
            bookID: bookID,
            bookTitle: bookTitle,
            chapter: chapter,
            pageNumber: pageNumber,
            locatorJSON: locatorJSON,
            contextSentence: contextSentence,
            fullDictionaryJSON: jsonData,
            createdAt: Date(),
            pinnedAt: nil
        )
    }
}
