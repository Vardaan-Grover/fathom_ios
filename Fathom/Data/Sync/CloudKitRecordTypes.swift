import CloudKit
import Foundation

// MARK: - Record type constants

nonisolated enum CKRecordType {
    static let book                    = "Book"
    static let bookCompletion          = "BookCompletion"
    static let bookCategory            = "BookCategory"
    static let bookCategoryMembership  = "BookCategoryMembership"
    static let highlight               = "Highlight"
    static let note                    = "Note"
    static let bookmark                = "Bookmark"
    static let savedWord               = "SavedWord"
    static let readingActivity         = "ReadingActivity"
    static let readingPosition         = "ReadingPosition"
    static let readerSettings          = "ReaderSettings"
    static let userProfile             = "UserProfile"

    /// Every type the engine pushes and applies.
    ///
    /// `AIConversation` is deliberately absent. The feature is dormant behind
    /// `FeatureFlags.aiCompanionEnabled`, its apply path is known-broken, and
    /// CloudKit's production schema is additive-only — a record type deployed
    /// once can never be removed or retyped. See §3.8 of the conflict policy.
    static let all: [String] = [
        book, bookCompletion, bookCategory, bookCategoryMembership,
        highlight, note, bookmark, savedWord,
        readingActivity, readingPosition, readerSettings, userProfile
    ]
}

// MARK: - Record names

/// Builds and parses CloudKit record names.
///
/// A record name identifies a record uniquely **within a zone, across all
/// record types** — CloudKit has no per-type namespace. The previous scheme
/// used the bare model UUID, which meant a `Book` and its `ReadingPosition`
/// both claimed `<bookID>` in the same zone and could not coexist. Nothing
/// caught it because the sync path had never run against real CloudKit.
///
/// Names are therefore type-prefixed: `Book.<uuid>`, `ReadingPosition.<uuid>`.
/// That removes the collision and makes names self-describing, which is what
/// lets the push path recover a record's type from its ID alone.
///
/// Only characters CloudKit accepts in a record name are used — ASCII letters,
/// digits, `-`, `_` and `.`. The composite membership key previously joined its
/// two UUIDs with `|`, which is not in that set; it now joins with `_`.
nonisolated enum CKRecordName {

    private static let separator: Character = "."

    static func make(type: CKRecord.RecordType, localID: String) -> String {
        "\(type)\(separator)\(localID)"
    }

    static func id(type: CKRecord.RecordType,
                   localID: String,
                   zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: make(type: type, localID: localID), zoneID: zoneID)
    }

    /// Splits a record name back into its type and local identifier.
    /// Returns nil for names that predate this scheme or are otherwise unknown.
    static func parse(_ recordName: String) -> (type: String, localID: String)? {
        guard let idx = recordName.firstIndex(of: separator) else { return nil }
        let type = String(recordName[recordName.startIndex..<idx])
        let localID = String(recordName[recordName.index(after: idx)...])
        guard !type.isEmpty, !localID.isEmpty, CKRecordType.all.contains(type) else { return nil }
        return (type, localID)
    }

    /// The local identifier for a record, or nil when the name is not ours.
    static func localID(of record: CKRecord) -> String? {
        parse(record.recordID.recordName)?.localID
    }

    /// Composite key for a category membership.
    static func membershipLocalID(bookID: UUID, categoryID: UUID) -> String {
        "\(bookID.uuidString)_\(categoryID.uuidString)"
    }

    static func parseMembership(localID: String) -> (bookID: UUID, categoryID: UUID)? {
        let parts = localID.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let bookID = UUID(uuidString: parts[0]),
              let categoryID = UUID(uuidString: parts[1]) else { return nil }
        return (bookID, categoryID)
    }
}

// MARK: - Helpers

private extension CKRecord {
    /// Sets `key` to `value`, or clears it when `value` is nil.
    ///
    /// Clearing matters: an explicit nil is how a cleared rating or a deleted
    /// reflection travels. The previous implementation skipped nils entirely,
    /// which made erasure unrepresentable and is exactly the bug the three-way
    /// merge exists to fix — a field can only be "deliberately cleared" if the
    /// record is capable of carrying its absence.
    ///
    /// One overload per value kind: Swift bridges a non-optional `String` to
    /// `__CKRecordObjCValue` implicitly, but will not do the same for
    /// `String?` into `(any __CKRecordObjCValue)?`, so the bridge is explicit.
    nonisolated func set(_ key: String, _ value: String?) {
        self[key] = value.map { $0 as NSString }
    }
    nonisolated func set(_ key: String, _ value: Int?) {
        self[key] = value.map { NSNumber(value: $0) }
    }
    nonisolated func set(_ key: String, _ value: Double?) {
        self[key] = value.map { NSNumber(value: $0) }
    }
    nonisolated func set(_ key: String, _ value: Date?) {
        self[key] = value.map { $0 as NSDate }
    }
    nonisolated func set(_ key: String, _ value: Data?) {
        self[key] = value.map { $0 as NSData }
    }
}

/// A model that can be written into, and read out of, a CKRecord.
nonisolated protocol CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { get }
    /// Identifier within the record type — the part after the type prefix.
    nonisolated var ckLocalID: String { get }
    /// Writes this model's fields onto an existing record, preserving whatever
    /// system fields (notably the change tag) the record already carries.
    nonisolated func apply(to record: CKRecord)
}

extension CloudKitSyncable {
    /// Convenience for tests and for the first push of a record the server has
    /// never seen.
    nonisolated func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: Self.ckRecordType,
            recordID: CKRecordName.id(type: Self.ckRecordType,
                                      localID: ckLocalID,
                                      zoneID: zoneID)
        )
        apply(to: record)
        return record
    }
}

// MARK: - Book

extension Book: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.book }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["title"] = title
        r.set("author", author)
        r["format"] = format.rawValue
        r.set("localFilename", localFilename)
        r.set("description", description)
        r.set("language", language)
        r.set("publisher", publisher)
        r.set("coverFilename", coverFilename)
        r["importDate"] = importDate
        r.set("contentHash", contentHash)
        r.set("estimatedPageCount", estimatedPageCount)
        r.set("estimatedReadingTimeMinutes", estimatedReadingTimeMinutes)
        r.set("lastReadAt", lastReadAt)
        r["modifiedAt"] = modifiedAt

        // rating, reflection, reflectionImageFilename and finishedAt live on
        // BookCompletion. Everything left here is extracted from the EPUB at
        // import and is identical on every device, which is what lets Book be
        // treated as immutable. See §3.1 of docs/sync-conflict-policy.md.
        //
        // preprocessingStatus, aiAnalysisProgress, aiEnabled and backendBookID
        // are deliberately not synced. They describe work done to *this
        // device's* copy of the file; telling another device that its own copy
        // is `.ready` when it has never processed it is worse than telling it
        // nothing. See §3.2 of the conflict policy.
    }

    /// Builds a Book from a record. Fields that are not synced take the
    /// caller's local values — see `SyncEngine.apply` for how existing rows
    /// preserve them.
    nonisolated static func from(ckRecord r: CKRecord) -> Book? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let title = r["title"] as? String,
            let fmtRaw = r["format"] as? String,
            let format = BookFormat(rawValue: fmtRaw),
            let importDate = r["importDate"] as? Date
        else { return nil }

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
            preprocessingStatus: .pending,
            aiAnalysisProgress: 0,
            aiEnabled: false,
            backendBookID: nil,
            contentHash: r["contentHash"] as? String,
            estimatedPageCount: r["estimatedPageCount"] as? Int,
            estimatedReadingTimeMinutes: r["estimatedReadingTimeMinutes"] as? Int,
            lastReadAt: r["lastReadAt"] as? Date,
            modifiedAt: r["modifiedAt"] as? Date ?? importDate
        )
    }
}

// MARK: - BookCompletion

extension BookCompletion: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.bookCompletion }
    nonisolated var ckLocalID: String { bookID.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r.set("rating", rating)
        r.set("reflection", reflection)
        r.set("reflectionImageFilename", reflectionImageFilename)
        r["finishedAt"] = finishedAt
        r["modifiedAt"] = modifiedAt
    }

    nonisolated static func from(ckRecord r: CKRecord) -> BookCompletion? {
        guard
            let localID = CKRecordName.localID(of: r),
            let bookID = UUID(uuidString: localID),
            let finishedAt = r["finishedAt"] as? Date
        else { return nil }

        return BookCompletion(
            bookID: bookID,
            rating: r["rating"] as? Int,
            reflection: r["reflection"] as? String,
            reflectionImageFilename: r["reflectionImageFilename"] as? String,
            finishedAt: finishedAt,
            modifiedAt: r["modifiedAt"] as? Date ?? finishedAt
        )
    }
}

// MARK: - BookCategory

extension BookCategory: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.bookCategory }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["name"] = name
        r["shelfColorHex"] = shelfColorHex
        r["createdAt"] = createdAt
        r["sortOrder"] = sortOrder
        r["modifiedAt"] = modifiedAt
    }

    nonisolated static func from(ckRecord r: CKRecord) -> BookCategory? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let name = r["name"] as? String,
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

extension BookCategoryMembership: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.bookCategoryMembership }
    nonisolated var ckLocalID: String {
        CKRecordName.membershipLocalID(bookID: bookID, categoryID: categoryID)
    }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r["categoryID"] = categoryID.uuidString
        r["addedAt"] = addedAt
        r["sortOrder"] = sortOrder
        r["modifiedAt"] = modifiedAt
        r.set("deletedAt", deletedAt)
    }

    nonisolated static func from(ckRecord r: CKRecord) -> BookCategoryMembership? {
        guard
            let bookIDStr = r["bookID"] as? String,
            let catIDStr = r["categoryID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let categoryID = UUID(uuidString: catIDStr),
            let addedAt = r["addedAt"] as? Date
        else { return nil }

        return BookCategoryMembership(
            bookID: bookID,
            categoryID: categoryID,
            addedAt: addedAt,
            sortOrder: r["sortOrder"] as? Int ?? 0,
            modifiedAt: r["modifiedAt"] as? Date ?? addedAt,
            deletedAt: r["deletedAt"] as? Date
        )
    }
}

// MARK: - Highlight

extension Highlight: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.highlight }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r["locatorJSON"] = locatorJSON
        r["text"] = text
        r["createdAt"] = createdAt
        r["color"] = color.rawValue
        r.set("deletedAt", deletedAt)
        r["modifiedAt"] = modifiedAt
    }

    nonisolated static func from(ckRecord r: CKRecord) -> Highlight? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let bookIDStr = r["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let locatorJSON = r["locatorJSON"] as? String,
            let text = r["text"] as? String,
            let createdAt = r["createdAt"] as? Date,
            let colorRaw = r["color"] as? String,
            let color = HighlightColor(rawValue: colorRaw)
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

extension Note: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.note }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r["locatorJSON"] = locatorJSON
        r["selectedText"] = selectedText
        r["noteContent"] = noteContent
        r["createdAt"] = createdAt
        r.set("chapterTitle", chapterTitle)
        r.set("pageNumber", pageNumber)
        r["highlightColor"] = highlightColor.rawValue
        r.set("deletedAt", deletedAt)
        r["modifiedAt"] = modifiedAt
    }

    nonisolated static func from(ckRecord r: CKRecord) -> Note? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let bookIDStr = r["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let locatorJSON = r["locatorJSON"] as? String,
            let selectedText = r["selectedText"] as? String,
            let noteContent = r["noteContent"] as? String,
            let createdAt = r["createdAt"] as? Date,
            let colorRaw = r["highlightColor"] as? String,
            let color = HighlightColor(rawValue: colorRaw)
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

extension Bookmark: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.bookmark }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r["locatorJSON"] = locatorJSON
        r["progression"] = progression
        r["createdAt"] = createdAt
        r.set("chapterTitle", chapterTitle)
        r.set("pageNumber", pageNumber)
        r.set("deletedAt", deletedAt)
        r["modifiedAt"] = modifiedAt
    }

    nonisolated static func from(ckRecord r: CKRecord) -> Bookmark? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let bookIDStr = r["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let locatorJSON = r["locatorJSON"] as? String,
            let progression = r["progression"] as? Double,
            let createdAt = r["createdAt"] as? Date
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

extension SavedWord: CloudKitSyncable {
    public nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.savedWord }
    public nonisolated var ckLocalID: String { id.uuidString }

    public nonisolated func apply(to r: CKRecord) {
        r["word"] = word
        r["language"] = language
        r["partsOfSpeech"] = partsOfSpeech
        r.set("bookID", bookID?.uuidString)
        r.set("bookTitle", bookTitle)
        r.set("chapter", chapter)
        r.set("pageNumber", pageNumber)
        r.set("locatorJSON", locatorJSON)
        r.set("contextSentence", contextSentence)
        r.set("fullDictionaryJSON", fullDictionaryJSON)
        r["createdAt"] = createdAt
        r.set("pinnedAt", pinnedAt)
        r.set("deletedAt", deletedAt)
        r["modifiedAt"] = modifiedAt
    }

    public nonisolated static func from(ckRecord r: CKRecord) -> SavedWord? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let word = r["word"] as? String,
            let language = r["language"] as? String,
            let partsOfSpeech = r["partsOfSpeech"] as? String,
            let createdAt = r["createdAt"] as? Date
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

// MARK: - ReadingActivity

extension ReadingActivity: CloudKitSyncable {
    nonisolated static var ckRecordType: CKRecord.RecordType { CKRecordType.readingActivity }
    nonisolated var ckLocalID: String { id.uuidString }

    nonisolated func apply(to r: CKRecord) {
        r["bookID"] = bookID.uuidString
        r["date"] = date
        r["duration"] = duration
        r["createdAt"] = createdAt
        r["modifiedAt"] = modifiedAt
        r["deviceID"] = deviceID
    }

    nonisolated static func from(ckRecord r: CKRecord) -> ReadingActivity? {
        guard
            let localID = CKRecordName.localID(of: r),
            let id = UUID(uuidString: localID),
            let bookIDStr = r["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let date = r["date"] as? String,
            let duration = r["duration"] as? Double,
            let createdAt = r["createdAt"] as? Date
        else { return nil }

        return ReadingActivity(
            id: id,
            bookID: bookID,
            date: date,
            duration: duration,
            createdAt: createdAt,
            modifiedAt: r["modifiedAt"] as? Date ?? createdAt,
            // Rows predating the per-device key are attributed to whichever
            // device wrote them; an absent value means the record was written
            // before v30 and belongs to no device this build can identify.
            deviceID: r["deviceID"] as? String ?? ""
        )
    }
}
