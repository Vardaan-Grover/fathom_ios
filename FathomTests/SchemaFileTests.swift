import CloudKit
import Foundation
import Testing

@testable import Fathom

/// Keeps `CloudKit/schema.ckdb` honest against the code.
///
/// The schema file is applied to CloudKit by hand, and production schema is
/// additive-only — a field deployed is a field forever. So the failure mode
/// worth guarding is silent drift: someone adds a field to `apply(to:)`, never
/// touches the schema, and the mismatch only surfaces as a rejected save
/// against a real container. These tests turn that into a failing build.
struct SchemaFileTests {

    // MARK: - Schema file parsing

    /// Locates the schema file relative to this source file, so the test needs
    /// no bundled resource and reads exactly what is committed.
    nonisolated private static func schemaText() throws -> String {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()   // FathomTests/
            .deletingLastPathComponent()   // repo root
        let url = repoRoot.appending(path: "CloudKit/schema.ckdb")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// record type name → declared field names (system `___` fields excluded).
    nonisolated private static func parseSchema() throws -> [String: Set<String>] {
        var text = try schemaText()

        // Strip /* ... */ comments so prose cannot be mistaken for a field.
        while let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }

        var result: [String: Set<String>] = [:]
        let scanner = text.components(separatedBy: "RECORD TYPE ").dropFirst()
        for block in scanner {
            guard let nameEnd = block.firstIndex(of: "("),
                  let bodyEnd = block.range(of: ");") else { continue }
            let name = block[block.startIndex..<nameEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = block[block.index(after: nameEnd)..<bodyEnd.lowerBound]

            var fields = Set<String>()
            for line in body.components(separatedBy: ",") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("GRANT"), !trimmed.hasPrefix("\"___") else {
                    continue
                }
                if let field = trimmed.split(separator: " ").first {
                    fields.insert(String(field))
                }
            }
            result[name] = fields
        }
        return result
    }

    // MARK: - Record types

    @Test("The schema declares exactly the record types the engine syncs")
    func recordTypesMatch() throws {
        let schema = try Self.parseSchema()
        let declared = Set(schema.keys)
        let synced = Set(CKRecordType.all)

        #expect(synced.subtracting(declared).isEmpty,
                "record types the engine pushes but the schema omits: \(synced.subtracting(declared).sorted())")
        // The other direction matters just as much: production schema cannot be
        // reduced, so a type in this file that nothing syncs would be
        // permanent dead weight.
        #expect(declared.subtracting(synced).isEmpty,
                "record types in the schema that nothing syncs: \(declared.subtracting(synced).sorted())")
    }

    @Test("AIConversation is not in the schema")
    func aiConversationIsExcluded() throws {
        // Dormant behind a feature flag, and its apply path is known-broken.
        // Deploying it would lock in a shape nobody has validated. See §3.8.
        #expect(try Self.parseSchema()["AIConversation"] == nil)
    }

    // MARK: - Fields

    /// Builds a fully-populated record for each `CloudKitSyncable` type, so
    /// every optional field is present and gets compared.
    nonisolated private static func populatedRecords() -> [CKRecord] {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let now = Date()

        var book = Book(id: UUID(), title: "Cosmos", author: "Sagan",
                        format: .epub, localFilename: "c.epub")
        book.description = "An epic."
        book.language = "en"
        book.publisher = "Press"
        book.coverFilename = "cover.png"
        book.contentHash = "abc"
        book.estimatedPageCount = 400
        book.estimatedReadingTimeMinutes = 600
        book.lastReadAt = now

        let models: [any CloudKitSyncable] = [
            book,
            BookCompletion(bookID: UUID(), rating: 5, reflection: "Good.",
                           reflectionImageFilename: "r.png", finishedAt: now),
            BookCategory(id: UUID(), name: "Sky", shelfColorHex: "112233", createdAt: now),
            BookCategoryMembership(bookID: UUID(), categoryID: UUID(), addedAt: now,
                                   sortOrder: 1, modifiedAt: now, deletedAt: now),
            Highlight(id: UUID(), bookID: UUID(), locatorJSON: "{}", text: "a line",
                      createdAt: now, color: .yellow, deletedAt: now),
            Note(bookID: UUID(), locatorJSON: "{}", selectedText: "p",
                 noteContent: "n", chapterTitle: "II", pageNumber: 4,
                 highlightColor: .blue, deletedAt: now),
            Bookmark(bookID: UUID(), locatorJSON: "{}", progression: 0.5,
                     chapterTitle: "III", pageNumber: 9, deletedAt: now),
            SavedWord(id: UUID(), word: "w", language: "en", partsOfSpeech: "noun",
                      bookID: UUID(), bookTitle: "t", chapter: "c", pageNumber: 1,
                      locatorJSON: "{}", contextSentence: "s",
                      fullDictionaryJSON: Data([0x01]), createdAt: now,
                      pinnedAt: now, deletedAt: now),
            ReadingActivity(id: UUID(), bookID: UUID(), date: "2026-08-22",
                            duration: 60, createdAt: now, deviceID: "d"),
        ]
        return models.map { $0.toCKRecord(zoneID: zoneID) }
    }

    @Test("Every field the engine writes is declared in the schema")
    func writtenFieldsAreDeclared() throws {
        let schema = try Self.parseSchema()

        for record in Self.populatedRecords() {
            let declared = try #require(schema[record.recordType],
                                        "schema has no record type \(record.recordType)")
            let written = Set(record.allKeys())
            let missing = written.subtracting(declared)
            #expect(missing.isEmpty,
                    "\(record.recordType) writes fields the schema omits: \(missing.sorted())")
        }
    }

    @Test("The singleton records match the schema too")
    func singletonFieldsAreDeclared() throws {
        let schema = try Self.parseSchema()

        // These three are built inline in SyncEngine+Apply rather than through
        // CloudKitSyncable, so there is no record to introspect — the field
        // lists are mirrored here. If you change a builder, change this.
        let singletons: [String: Set<String>] = [
            CKRecordType.readingPosition: ["bookID", "locatorJSON", "savedAt",
                                           "furthestProgression"],
            CKRecordType.readerSettings: ["settingsJSON", "modifiedAt"],
            CKRecordType.userProfile: ["displayName", "avatarEmoji",
                                       "avatarColorHex", "modifiedAt"],
        ]

        for (type, written) in singletons {
            let declared = try #require(schema[type], "schema has no record type \(type)")
            #expect(written.subtracting(declared).isEmpty,
                    "\(type) writes fields the schema omits: \(written.subtracting(declared).sorted())")
            #expect(declared.subtracting(written).isEmpty,
                    "\(type) declares fields nothing writes: \(declared.subtracting(written).sorted())")
        }
    }

    @Test("The schema declares no field the engine never writes")
    func schemaHasNoDeadFields() throws {
        let schema = try Self.parseSchema()
        var written: [String: Set<String>] = [:]
        for record in Self.populatedRecords() {
            written[record.recordType, default: []].formUnion(record.allKeys())
        }

        for (type, fields) in written {
            let declared = try #require(schema[type])
            // A field in the schema that nothing writes is permanent once
            // deployed, so it is worth catching before it is.
            #expect(declared.subtracting(fields).isEmpty,
                    "\(type) declares fields nothing writes: \(declared.subtracting(fields).sorted())")
        }
    }
}
