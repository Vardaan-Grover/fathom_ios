import CloudKit
import Foundation

// MARK: - Record type constants

enum CKRecordType {
    static let book                    = "Book"
    static let bookCategory            = "BookCategory"
    static let bookCategoryMembership  = "BookCategoryMembership"
    static let highlight               = "Highlight"
    static let note                    = "Note"
    static let bookmark                = "Bookmark"
    static let savedWord               = "SavedWord"
    static let aiConversation          = "AIConversation"
    static let readingPosition         = "ReadingPosition"
    static let readerSettings          = "ReaderSettings"
}

// MARK: - Helpers

private extension CKRecord {
    /// Sets `key` to `value`, or does nothing when `value` is nil.
    /// Uses the concrete `__CKRecordObjCValue` existential that CKRecord's
    /// subscript expects (the Swift overlay changed names across SDK versions).
    func set(_ key: String, _ value: __CKRecordObjCValue?) {
        guard let value else { return }
        self[key] = value
    }
}

// MARK: - Book

extension Book {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.book, recordID: rid)
        r["title"]                       = title as CKRecordValue
        r.set("author",                    author as? CKRecordValue)
        r.set("format",                    format.rawValue as CKRecordValue)
        r.set("localFilename",             localFilename as? CKRecordValue)
        r.set("description",               description as? CKRecordValue)
        r.set("language",                  language as? CKRecordValue)
        r.set("publisher",                 publisher as? CKRecordValue)
        r.set("coverFilename",             coverFilename as? CKRecordValue)
        r["importDate"]                  = importDate as CKRecordValue
        r["preprocessingStatus"]         = preprocessingStatus.rawValue as CKRecordValue
        r["aiEnabled"]                   = (aiEnabled ? 1 : 0) as CKRecordValue
        r.set("backendBookID",             backendBookID?.uuidString as? CKRecordValue)
        r.set("contentHash",               contentHash as? CKRecordValue)
        r.set("estimatedPageCount",        estimatedPageCount as? CKRecordValue)
        r.set("estimatedReadingTimeMinutes", estimatedReadingTimeMinutes as? CKRecordValue)
        r.set("lastReadAt",                lastReadAt as? CKRecordValue)
        r["modifiedAt"]                  = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> Book? {
        guard
            let id     = UUID(uuidString: r.recordID.recordName),
            let title  = r["title"] as? String,
            let fmtRaw = r["format"] as? String,
            let format = BookFormat(rawValue: fmtRaw),
            let importDate = r["importDate"] as? Date
        else { return nil }

        let statusRaw = r["preprocessingStatus"] as? String ?? PreprocessingStatus.pending.rawValue
        let status    = PreprocessingStatus(rawValue: statusRaw) ?? .pending
        let aiEnabled = (r["aiEnabled"] as? Int ?? 0) != 0
        let modifiedAt = r["modifiedAt"] as? Date ?? importDate

        return Book(
            id: id,
            title: title,
            author: r["author"] as? String,
            format: format,
            localFilename: r["localFilename"] as? String,
            description: r["description"] as? String,
            language: r["language"] as? String,
            publisher: r["publisher"] as? String,
            coverFilename: r["coverFilename"] as? String,
            importDate: importDate,
            preprocessingStatus: status,
            aiAnalysisProgress: 0,
            aiEnabled: aiEnabled,
            backendBookID: (r["backendBookID"] as? String).flatMap(UUID.init),
            contentHash: r["contentHash"] as? String,
            estimatedPageCount: r["estimatedPageCount"] as? Int,
            estimatedReadingTimeMinutes: r["estimatedReadingTimeMinutes"] as? Int,
            lastReadAt: r["lastReadAt"] as? Date,
            modifiedAt: modifiedAt
        )
    }
}

// MARK: - BookCategory

extension BookCategory {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.bookCategory, recordID: rid)
        r["name"]          = name as CKRecordValue
        r["shelfColorHex"] = shelfColorHex as CKRecordValue
        r["createdAt"]     = createdAt as CKRecordValue
        r["sortOrder"]     = sortOrder as CKRecordValue
        r["modifiedAt"]    = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> BookCategory? {
        guard
            let id    = UUID(uuidString: r.recordID.recordName),
            let name  = r["name"] as? String,
            let color = r["shelfColorHex"] as? String,
            let createdAt = r["createdAt"] as? Date
        else { return nil }

        return BookCategory(
            id: id,
            name: name,
            shelfColorHex: color,
            createdAt: createdAt,
            sortOrder: r["sortOrder"] as? Int ?? 0,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt
        )
    }
}

// MARK: - BookCategoryMembership
// recordName is "bookID|categoryID"

extension BookCategoryMembership {
    var ckRecordName: String { "\(bookID.uuidString)|\(categoryID.uuidString)" }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: ckRecordName, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.bookCategoryMembership, recordID: rid)
        r["bookID"]     = bookID.uuidString as CKRecordValue
        r["categoryID"] = categoryID.uuidString as CKRecordValue
        r["addedAt"]    = addedAt as CKRecordValue
        r["sortOrder"]  = sortOrder as CKRecordValue
        r["modifiedAt"] = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> BookCategoryMembership? {
        guard
            let bookIDStr  = r["bookID"] as? String,
            let catIDStr   = r["categoryID"] as? String,
            let bookID     = UUID(uuidString: bookIDStr),
            let categoryID = UUID(uuidString: catIDStr),
            let addedAt    = r["addedAt"] as? Date
        else { return nil }

        return BookCategoryMembership(
            bookID: bookID,
            categoryID: categoryID,
            addedAt: addedAt,
            sortOrder: r["sortOrder"] as? Int ?? 0,
            modifiedAt: r["modifiedAt"] as? Date ?? addedAt
        )
    }
}

// MARK: - Highlight

extension Highlight {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.highlight, recordID: rid)
        r["bookID"]      = bookID.uuidString as CKRecordValue
        r["locatorJSON"] = locatorJSON as CKRecordValue
        r["text"]        = text as CKRecordValue
        r["createdAt"]   = createdAt as CKRecordValue
        r["color"]       = color.rawValue as CKRecordValue
        r.set("deletedAt", deletedAt as? CKRecordValue)
        r["modifiedAt"]  = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> Highlight? {
        guard
            let id          = UUID(uuidString: r.recordID.recordName),
            let bookIDStr   = r["bookID"] as? String,
            let bookID      = UUID(uuidString: bookIDStr),
            let locatorJSON = r["locatorJSON"] as? String,
            let text        = r["text"] as? String,
            let createdAt   = r["createdAt"] as? Date,
            let colorRaw    = r["color"] as? String,
            let color       = HighlightColor(rawValue: colorRaw)
        else { return nil }

        return Highlight(
            id: id,
            bookID: bookID,
            locatorJSON: locatorJSON,
            text: text,
            createdAt: createdAt,
            color: color,
            deletedAt: r["deletedAt"] as? Date,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt
        )
    }
}

// MARK: - Note

extension Note {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.note, recordID: rid)
        r["bookID"]        = bookID.uuidString as CKRecordValue
        r["locatorJSON"]   = locatorJSON as CKRecordValue
        r["selectedText"]  = selectedText as CKRecordValue
        r["noteContent"]   = noteContent as CKRecordValue
        r["createdAt"]     = createdAt as CKRecordValue
        r.set("chapterTitle",  chapterTitle as? CKRecordValue)
        r.set("pageNumber",    pageNumber as? CKRecordValue)
        r["highlightColor"] = highlightColor.rawValue as CKRecordValue
        r.set("deletedAt",    deletedAt as? CKRecordValue)
        r["modifiedAt"]    = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> Note? {
        guard
            let id           = UUID(uuidString: r.recordID.recordName),
            let bookIDStr    = r["bookID"] as? String,
            let bookID       = UUID(uuidString: bookIDStr),
            let locatorJSON  = r["locatorJSON"] as? String,
            let selectedText = r["selectedText"] as? String,
            let noteContent  = r["noteContent"] as? String,
            let createdAt    = r["createdAt"] as? Date,
            let colorRaw     = r["highlightColor"] as? String,
            let color        = HighlightColor(rawValue: colorRaw)
        else { return nil }

        return Note(
            id: id,
            bookID: bookID,
            locatorJSON: locatorJSON,
            selectedText: selectedText,
            noteContent: noteContent,
            createdAt: createdAt,
            chapterTitle: r["chapterTitle"] as? String,
            pageNumber: r["pageNumber"] as? Int,
            highlightColor: color,
            deletedAt: r["deletedAt"] as? Date,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt
        )
    }
}

// MARK: - Bookmark

extension Bookmark {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.bookmark, recordID: rid)
        r["bookID"]      = bookID.uuidString as CKRecordValue
        r["locatorJSON"] = locatorJSON as CKRecordValue
        r["progression"] = progression as CKRecordValue
        r["createdAt"]   = createdAt as CKRecordValue
        r.set("chapterTitle", chapterTitle as? CKRecordValue)
        r.set("pageNumber",   pageNumber as? CKRecordValue)
        r.set("deletedAt",    deletedAt as? CKRecordValue)
        r["modifiedAt"]  = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> Bookmark? {
        guard
            let id          = UUID(uuidString: r.recordID.recordName),
            let bookIDStr   = r["bookID"] as? String,
            let bookID      = UUID(uuidString: bookIDStr),
            let locatorJSON = r["locatorJSON"] as? String,
            let progression = r["progression"] as? Double,
            let createdAt   = r["createdAt"] as? Date
        else { return nil }

        return Bookmark(
            id: id,
            bookID: bookID,
            locatorJSON: locatorJSON,
            progression: progression,
            chapterTitle: r["chapterTitle"] as? String,
            pageNumber: r["pageNumber"] as? Int,
            createdAt: createdAt,
            deletedAt: r["deletedAt"] as? Date,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt
        )
    }
}

// MARK: - SavedWord

extension SavedWord {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.savedWord, recordID: rid)
        r["word"]           = word as CKRecordValue
        r["language"]       = language as CKRecordValue
        r["partsOfSpeech"]  = partsOfSpeech as CKRecordValue
        r.set("bookID",       bookID?.uuidString as? CKRecordValue)
        r.set("bookTitle",    bookTitle as? CKRecordValue)
        r.set("chapter",      chapter as? CKRecordValue)
        r.set("pageNumber",   pageNumber as? CKRecordValue)
        r.set("locatorJSON",  locatorJSON as? CKRecordValue)
        r.set("contextSentence", contextSentence as? CKRecordValue)
        if let json = fullDictionaryJSON {
            r["fullDictionaryJSON"] = json as CKRecordValue
        }
        r["createdAt"]      = createdAt as CKRecordValue
        r.set("pinnedAt",     pinnedAt as? CKRecordValue)
        r.set("deletedAt",    deletedAt as? CKRecordValue)
        r["modifiedAt"]     = modifiedAt as CKRecordValue
        return r
    }

    static func from(ckRecord r: CKRecord) -> SavedWord? {
        guard
            let id           = UUID(uuidString: r.recordID.recordName),
            let word         = r["word"] as? String,
            let language     = r["language"] as? String,
            let partsOfSpeech = r["partsOfSpeech"] as? String,
            let createdAt    = r["createdAt"] as? Date
        else { return nil }

        return SavedWord(
            id: id,
            word: word,
            language: language,
            partsOfSpeech: partsOfSpeech,
            bookID: (r["bookID"] as? String).flatMap(UUID.init),
            bookTitle: r["bookTitle"] as? String,
            chapter: r["chapter"] as? String,
            pageNumber: r["pageNumber"] as? Int,
            locatorJSON: r["locatorJSON"] as? String,
            contextSentence: r["contextSentence"] as? String,
            fullDictionaryJSON: r["fullDictionaryJSON"] as? Data,
            createdAt: createdAt,
            pinnedAt: r["pinnedAt"] as? Date,
            deletedAt: r["deletedAt"] as? Date,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt
        )
    }
}

// MARK: - AIConversation
// Messages are embedded as a JSON blob to keep record count manageable.

extension AIThread {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.aiConversation, recordID: rid)
        r["bookID"]       = bookID.uuidString as CKRecordValue
        r["passageText"]  = passageText as CKRecordValue
        r["createdAt"]    = createdAt as CKRecordValue
        r.set("locatorJSON",  locatorJSON as? CKRecordValue)
        r.set("chapterTitle", chapterTitle as? CKRecordValue)
        if let blob = try? JSONEncoder().encode(messages) {
            r["messagesJSON"] = blob as CKRecordValue
        }
        return r
    }

    static func from(ckRecord r: CKRecord) -> AIThread? {
        guard
            let id          = UUID(uuidString: r.recordID.recordName),
            let bookIDStr   = r["bookID"] as? String,
            let bookID      = UUID(uuidString: bookIDStr),
            let passageText = r["passageText"] as? String,
            let createdAt   = r["createdAt"] as? Date
        else { return nil }

        let messages: [AIMessage]
        if let blob = r["messagesJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([AIMessage].self, from: blob) {
            messages = decoded
        } else {
            messages = []
        }

        return AIThread(
            id: id,
            bookID: bookID,
            passageText: passageText,
            locatorJSON: r["locatorJSON"] as? String,
            chapterTitle: r["chapterTitle"] as? String,
            createdAt: createdAt,
            messages: messages
        )
    }
}
