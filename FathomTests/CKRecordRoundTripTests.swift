import CloudKit
import Foundation
import Testing

@testable import Fathom

/// CKRecord ⇄ model conversions. These guard the sync contract — in
/// particular that every persisted field survives the round trip (a missing
/// field here means data silently reset to nil on the next pull).
struct CKRecordRoundTripTests {

    private let zoneID = CKRecordZone.ID(
        zoneName: "test-zone", ownerName: CKCurrentUserDefaultName)

    @Test func bookRoundTripPreservesAllSyncedFields() throws {
        var book = Book(
            id: UUID(), title: "The Odyssey", author: "Homer",
            format: .epub, localFilename: "odyssey.epub")
        book.description = "An epic."
        book.language = "en"
        book.publisher = "Ancient Press"
        book.coverFilename = "cover.png"
        book.aiEnabled = true
        book.backendBookID = UUID()
        book.contentHash = "abc123"
        book.estimatedPageCount = 400
        book.estimatedReadingTimeMinutes = 600
        book.lastReadAt = Date(timeIntervalSince1970: 1_750_000_000)

        let decoded = try #require(Book.from(ckRecord: book.toCKRecord(zoneID: zoneID)))

        #expect(decoded.id == book.id)
        #expect(decoded.title == book.title)
        #expect(decoded.author == book.author)
        #expect(decoded.format == book.format)
        #expect(decoded.localFilename == book.localFilename)
        #expect(decoded.description == book.description)
        #expect(decoded.language == book.language)
        #expect(decoded.publisher == book.publisher)
        #expect(decoded.coverFilename == book.coverFilename)
        // Device-local fields are deliberately NOT carried on the record.
        // preprocessingStatus, aiAnalysisProgress, aiEnabled and backendBookID
        // describe work done to *this device's* copy of the file; telling
        // another device its own copy is ready when it has never processed it
        // is worse than telling it nothing. `SyncEngine.apply` keeps the
        // existing local values when updating a row. See §3.2 of
        // docs/sync-conflict-policy.md.
        #expect(decoded.aiEnabled == false)
        #expect(decoded.backendBookID == nil)
        #expect(decoded.preprocessingStatus == .pending)
        #expect(decoded.aiAnalysisProgress == 0)
        #expect(decoded.contentHash == book.contentHash)
        #expect(decoded.estimatedPageCount == book.estimatedPageCount)
        #expect(decoded.estimatedReadingTimeMinutes == book.estimatedReadingTimeMinutes)
        #expect(decoded.lastReadAt == book.lastReadAt)
    }

    @Test func highlightRoundTrip() throws {
        let highlight = Highlight(
            id: UUID(), bookID: UUID(), locatorJSON: "{\"href\":\"ch1\"}",
            text: "memorable line", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            color: .pink, deletedAt: Date(timeIntervalSince1970: 1_710_000_000))

        let decoded = try #require(Highlight.from(ckRecord: highlight.toCKRecord(zoneID: zoneID)))

        #expect(decoded.id == highlight.id)
        #expect(decoded.bookID == highlight.bookID)
        #expect(decoded.locatorJSON == highlight.locatorJSON)
        #expect(decoded.text == highlight.text)
        #expect(decoded.color == highlight.color)
        #expect(decoded.deletedAt == highlight.deletedAt)
    }

    @Test func noteRoundTrip() throws {
        let note = Note(
            bookID: UUID(), locatorJSON: "{}", selectedText: "passage",
            noteContent: "my thought", chapterTitle: "Chapter 2",
            pageNumber: 42, highlightColor: .blue)

        let decoded = try #require(Note.from(ckRecord: note.toCKRecord(zoneID: zoneID)))

        #expect(decoded.id == note.id)
        #expect(decoded.noteContent == note.noteContent)
        #expect(decoded.chapterTitle == note.chapterTitle)
        #expect(decoded.pageNumber == note.pageNumber)
        #expect(decoded.highlightColor == note.highlightColor)
        #expect(decoded.deletedAt == nil)
    }

    @Test func bookmarkRoundTrip() throws {
        let bookmark = Bookmark(
            bookID: UUID(), locatorJSON: "{}", progression: 0.37,
            chapterTitle: "III", pageNumber: 99)

        let decoded = try #require(Bookmark.from(ckRecord: bookmark.toCKRecord(zoneID: zoneID)))

        #expect(decoded.id == bookmark.id)
        #expect(decoded.progression == bookmark.progression)
        #expect(decoded.chapterTitle == bookmark.chapterTitle)
        #expect(decoded.pageNumber == bookmark.pageNumber)
    }

    @Test func readingActivityRoundTrip() throws {
        let activity = ReadingActivity(
            id: UUID(), bookID: UUID(), date: "2026-07-08",
            duration: 1234.5, createdAt: Date(timeIntervalSince1970: 1_720_000_000))

        let decoded = try #require(
            ReadingActivity.from(ckRecord: activity.toCKRecord(zoneID: zoneID)))

        #expect(decoded.id == activity.id)
        #expect(decoded.bookID == activity.bookID)
        #expect(decoded.date == activity.date)
        #expect(decoded.duration == activity.duration)
    }

    @Test func bookCategoryAndMembershipRoundTrip() throws {
        let category = BookCategory(
            id: UUID(), name: "Sci-Fi", shelfColorHex: "1A5EA8",
            createdAt: Date(timeIntervalSince1970: 1_690_000_000), sortOrder: 3)
        let decodedCategory = try #require(
            BookCategory.from(ckRecord: category.toCKRecord(zoneID: zoneID)))
        #expect(decodedCategory.name == category.name)
        #expect(decodedCategory.shelfColorHex == category.shelfColorHex)
        #expect(decodedCategory.sortOrder == category.sortOrder)

        let membership = BookCategoryMembership(
            bookID: UUID(), categoryID: category.id,
            addedAt: Date(timeIntervalSince1970: 1_695_000_000), sortOrder: 1)
        let decodedMembership = try #require(
            BookCategoryMembership.from(ckRecord: membership.toCKRecord(zoneID: zoneID)))
        #expect(decodedMembership.bookID == membership.bookID)
        #expect(decodedMembership.categoryID == membership.categoryID)
        #expect(decodedMembership.sortOrder == membership.sortOrder)
        // The composite key is what the CDC queue and apply path parse. It
        // joins with "_" rather than "|": record names are restricted to ASCII
        // letters, digits, "-", "_" and ".", and "|" is not among them.
        #expect(membership.ckLocalID
                == "\(membership.bookID.uuidString)_\(membership.categoryID.uuidString)")
        #expect(CKRecordName.parseMembership(localID: membership.ckLocalID)?.bookID
                == membership.bookID)
    }
}

/// The reader's completion data rides its own record — see §3.1 of
/// docs/sync-conflict-policy.md.
struct BookCompletionRecordTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    @Test func completionRoundTripsEveryField() throws {
        let completion = BookCompletion(
            bookID: UUID(),
            rating: 5,
            reflection: "Changed how I read.",
            reflectionImageFilename: "reflection.png",
            finishedAt: Date(timeIntervalSince1970: 1_760_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_770_000_000))

        let decoded = try #require(
            BookCompletion.from(ckRecord: completion.toCKRecord(zoneID: zoneID)))

        #expect(decoded.bookID == completion.bookID)
        #expect(decoded.rating == 5)
        #expect(decoded.reflection == completion.reflection)
        #expect(decoded.reflectionImageFilename == completion.reflectionImageFilename)
        #expect(decoded.finishedAt == completion.finishedAt)
        #expect(decoded.modifiedAt == completion.modifiedAt)
    }

    @Test func aBookRecordNoLongerCarriesCompletionFields() throws {
        // The point of the split: Book is now fixed at import, so its record
        // has nothing a second device could contend with. CloudKit's
        // production schema is additive-only, which is why this had to be
        // settled before the first deploy.
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let record = book.toCKRecord(zoneID: zoneID)

        for field in ["rating", "reflection", "reflectionImageFilename", "finishedAt"] {
            #expect(record[field] == nil, "Book record still carries \(field)")
        }
    }

    @Test func aBookAndItsCompletionDoNotShareARecordName() throws {
        let bookID = UUID()
        let book = Book(id: bookID, title: "Cosmos", author: "Sagan", format: .epub)
        let completion = BookCompletion(bookID: bookID, finishedAt: Date())

        // Record names are unique per zone across all types.
        #expect(book.toCKRecord(zoneID: zoneID).recordID.recordName
                != completion.toCKRecord(zoneID: zoneID).recordID.recordName)
    }
}
