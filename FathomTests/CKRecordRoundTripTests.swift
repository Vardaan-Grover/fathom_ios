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
        // Completion fields — regression guard for the pull-wipes-completion bug.
        book.rating = 5
        book.reflection = "Changed how I read."
        book.reflectionImageFilename = "reflection.png"
        book.finishedAt = Date(timeIntervalSince1970: 1_760_000_000)

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
        #expect(decoded.aiEnabled == book.aiEnabled)
        #expect(decoded.backendBookID == book.backendBookID)
        #expect(decoded.contentHash == book.contentHash)
        #expect(decoded.estimatedPageCount == book.estimatedPageCount)
        #expect(decoded.estimatedReadingTimeMinutes == book.estimatedReadingTimeMinutes)
        #expect(decoded.lastReadAt == book.lastReadAt)
        #expect(decoded.rating == book.rating)
        #expect(decoded.reflection == book.reflection)
        #expect(decoded.reflectionImageFilename == book.reflectionImageFilename)
        #expect(decoded.finishedAt == book.finishedAt)
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
        // The composite record name is what the CDC queue and pull path parse.
        #expect(membership.ckRecordName
                == "\(membership.bookID.uuidString)|\(membership.categoryID.uuidString)")
    }
}
