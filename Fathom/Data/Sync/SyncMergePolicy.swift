import CloudKit
import Foundation

// MARK: - Field merge behaviour

/// How a single field is resolved when two devices edited the same record
/// between syncs.
///
/// See `docs/sync-conflict-policy.md` for the reasoning behind each
/// assignment. This enum is the executable form of that document's table —
/// if the two ever disagree, the document is the specification and this is
/// the bug.
nonisolated enum FieldMerge: Equatable {

    /// The field's value is whatever the last writer set.
    ///
    /// Only reached when *both* sides changed the field since the common
    /// ancestor; when only one side changed it, that side wins outright and
    /// no policy is consulted. On a true concurrent edit the server's value
    /// wins — see `SyncMerge.resolve` for why that choice, and not a client
    /// timestamp, is the one that converges.
    case lastWriterWins

    /// A high-water mark rather than a value: `max(client, server)`.
    /// Used for progress and "last seen" timestamps, which only move forward.
    case maxWins

    /// A delete marker. A delete beats a concurrent edit regardless of which
    /// side is newer, and merge never clears one on its own. The only way a
    /// tombstone is cleared is an explicit user action on one side (re-adding
    /// a book to a shelf) while the other side left the marker alone — the
    /// ancestor is what tells those apart.
    case tombstone

    /// Fixed at creation. Both sides must already agree; if they do not, the
    /// server's value is kept and the disagreement is logged, because it means
    /// something upstream is wrong.
    case immutable
}

// MARK: - Policy table

nonisolated enum SyncMergePolicy {

    /// Fields whose merge behaviour differs from the record type's default.
    ///
    /// A key absent from this map falls through to `defaultMerge(for:)`. Keys
    /// may name fields that do not exist yet — the merge only consults keys
    /// actually present on the records in front of it, so listing a field
    /// ahead of its schema migration is harmless and keeps the policy and the
    /// document in step.
    static func fields(for recordType: CKRecord.RecordType) -> [String: FieldMerge] {
        switch recordType {

        case CKRecordType.book:
            return [
                // Derived from the EPUB file at import — identical on every
                // device by construction.
                "format": .immutable,
                "localFilename": .immutable,
                "contentHash": .immutable,
                "importDate": .immutable,
                "language": .immutable,
                "publisher": .immutable,
                "estimatedPageCount": .immutable,
                "estimatedReadingTimeMinutes": .immutable,
                // Editable by the reader, both at import and later from the
                // book's edit sheet. Treating these as immutable reverted a
                // rename — and a cover change, whose old file was already
                // deleted — on every conflict.
                "title": .lastWriterWins,
                "author": .lastWriterWins,
                "description": .lastWriterWins,
                "coverFilename": .lastWriterWins,
                // A high-water mark, not a value.
                "lastReadAt": .maxWins,
                "modifiedAt": .maxWins
            ]

        case CKRecordType.bookCompletion:
            return [
                "bookID": .immutable,
                "modifiedAt": .maxWins,
                // Every field here is written by the reader, and honestly
                // contended — this is the record the split exists to isolate.
                "rating": .lastWriterWins,
                "reflection": .lastWriterWins,
                "reflectionImageFilename": .lastWriterWins,
                "finishedAt": .lastWriterWins
            ]

        case CKRecordType.bookCategory:
            return [
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                "name": .lastWriterWins,
                "shelfColorHex": .lastWriterWins,
                // Known not to converge under concurrent reorder — accepted
                // deliberately for v1. See §3.5.
                "sortOrder": .lastWriterWins
            ]

        case CKRecordType.bookCategoryMembership:
            return [
                "bookID": .immutable,
                "categoryID": .immutable,
                "addedAt": .immutable,
                "modifiedAt": .maxWins,
                "sortOrder": .lastWriterWins,
                "deletedAt": .tombstone
            ]

        case CKRecordType.highlight:
            return [
                "bookID": .immutable,
                "locatorJSON": .immutable,
                "text": .immutable,
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                "color": .lastWriterWins,
                "deletedAt": .tombstone
            ]

        case CKRecordType.note:
            return [
                "bookID": .immutable,
                "locatorJSON": .immutable,
                "selectedText": .immutable,
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                "noteContent": .lastWriterWins,
                "chapterTitle": .lastWriterWins,
                "pageNumber": .lastWriterWins,
                "highlightColor": .lastWriterWins,
                "deletedAt": .tombstone
            ]

        case CKRecordType.bookmark:
            // A bookmark is created or removed, never edited.
            return [
                "bookID": .immutable,
                "locatorJSON": .immutable,
                "progression": .immutable,
                "chapterTitle": .immutable,
                "pageNumber": .immutable,
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                "deletedAt": .tombstone
            ]

        case CKRecordType.savedWord:
            return [
                "word": .immutable,
                "language": .immutable,
                "partsOfSpeech": .immutable,
                "bookID": .immutable,
                "bookTitle": .immutable,
                "chapter": .immutable,
                "pageNumber": .immutable,
                "locatorJSON": .immutable,
                "contextSentence": .immutable,
                // A deterministic dictionary lookup for a fixed word.
                "fullDictionaryJSON": .immutable,
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                "pinnedAt": .lastWriterWins,
                "deletedAt": .tombstone
            ]

        case CKRecordType.readingActivity:
            return [
                "bookID": .immutable,
                "date": .immutable,
                "deviceID": .immutable,
                "createdAt": .immutable,
                "modifiedAt": .maxWins,
                // Now keyed on (bookID, date, deviceID), so exactly one device
                // ever writes this row and a conflict should not arise. If one
                // somehow does, duration only ever grows within a day, which
                // makes the larger value the later one. See §3.4.
                "duration": .maxWins
            ]

        case CKRecordType.readingPosition:
            return [
                "bookID": .immutable,
                "locatorJSON": .lastWriterWins,
                "savedAt": .lastWriterWins,
                // Progress only moves forward. See §3.6.
                "furthestProgression": .maxWins
            ]

        case CKRecordType.readerSettings:
            // Deliberately a single blob — see §3.7.
            return [
                "settingsJSON": .lastWriterWins,
                "modifiedAt": .maxWins
            ]

        case CKRecordType.userProfile:
            return [
                "displayName": .lastWriterWins,
                "avatarEmoji": .lastWriterWins,
                "avatarColorHex": .lastWriterWins,
                "modifiedAt": .maxWins
            ]

        default:
            return [:]
        }
    }

    /// Behaviour for a field with no explicit entry above.
    ///
    /// Last-writer-wins is the safe fallback: it converges, and a field nobody
    /// thought about is far more likely to be an ordinary mutable value than
    /// an immutable one.
    static func defaultMerge(for recordType: CKRecord.RecordType) -> FieldMerge {
        _ = recordType
        return .lastWriterWins
    }

    static func merge(for recordType: CKRecord.RecordType, field: String) -> FieldMerge {
        fields(for: recordType)[field] ?? defaultMerge(for: recordType)
    }
}

// MARK: - Three-way merge

nonisolated enum SyncMerge {

    /// Produces the record to write back to the server after a
    /// `serverRecordChanged` conflict.
    ///
    /// The ancestor is the version both sides diverged from. Having it is what
    /// separates "this side deliberately cleared the field" from "this side
    /// never touched the field" — a distinction that is impossible with two
    /// records alone, and whose absence is why the previous engine could never
    /// propagate a cleared rating or a deleted reflection.
    ///
    /// The returned record is a copy of the *server* record with merged values
    /// applied, so it carries the server's change tag. `server` itself is left
    /// untouched.
    static func resolve(client: CKRecord,
                        server: CKRecord,
                        ancestor: CKRecord?) -> CKRecord {

        // CloudKit does not always supply an ancestor. It is absent whenever
        // the client record was never derived from a server version at all —
        // the "record to insert already exists" case, which is what a device
        // with an empty metadata cache and a populated zone produces. Without
        // it there is no structural information about who changed what, and
        // pretending otherwise makes every field read as contended and every
        // immutable field look like it diverged.
        //
        // An ancestor with no values at all is treated the same way. Builds
        // before full-record caching rebuilt every upload on a system-fields
        // archive, and CloudKit's ancestor for such an upload carries metadata
        // only — a three-way merge against it reads every field as changed on
        // both sides and always prefers the server.
        guard let ancestor, !ancestor.allKeys().isEmpty else {
            return resolveWithoutAncestor(client: client, server: server)
        }

        let type   = server.recordType
        let merged = copy(of: server)    // carries the current change tag
        let keys   = Set(client.allKeys())
            .union(server.allKeys())
            .union(ancestor.allKeys())

        for key in keys {
            let clientValue   = client[key]
            let serverValue   = server[key]

            // Two sides that already agree are not in conflict, whatever the
            // ancestor says. This is not just an optimisation: CloudKit's
            // ancestor for a record this device never fetched carries system
            // fields but no user values, so without this check every field
            // reads as contended and every immutable one gets reported as
            // diverged. The first real run logged that for all 250 records —
            // describing values that were identical on both sides.
            if equal(clientValue, serverValue) { continue }

            let ancestorValue = ancestor[key]

            let clientChanged = !equal(clientValue, ancestorValue)
            let serverChanged = !equal(serverValue, ancestorValue)

            let policy = SyncMergePolicy.merge(for: type, field: key)

            // Tombstones: a side that touched the marker when the other did not
            // wins — that is a delete, or an explicit undelete such as putting
            // a book back on a shelf. When both touched it, the delete wins.
            if policy == .tombstone {
                switch (clientChanged, serverChanged) {
                case (true, false):
                    merged[key] = clientValue
                case (false, _):
                    break   // server value already in place
                case (true, true):
                    merged[key] = firstNonNil(serverValue, clientValue)
                }
                continue
            }

            switch (clientChanged, serverChanged) {

            case (false, false):
                // Neither side touched it. Server value already in place.
                continue

            case (true, false):
                // Only this device changed it — including a deliberate clear,
                // which is the case the old nil-coalescing hack could not
                // express.
                merged[key] = clientValue

            case (false, true):
                // Only the other device changed it. Already in place.
                continue

            case (true, true):
                merged[key] = resolveContended(policy: policy,
                                               key: key,
                                               type: type,
                                               client: clientValue,
                                               server: serverValue)
            }
        }

        return merged
    }

    /// Merges when CloudKit gave us no common ancestor.
    ///
    /// Nothing here can distinguish "this side changed the field" from "this
    /// side never touched it", so the field-level reasoning the three-way merge
    /// depends on is unavailable. What is left is the record's own
    /// `modifiedAt` — the client wall-clock this policy otherwise refuses to
    /// trust (§0.1). It is used *only* here, because the alternative is worse:
    /// always preferring the server silently discards a local edit that was
    /// never pushed, which is exactly the data loss the policy exists to stop.
    ///
    /// Field policies that do not need an ancestor still apply: a tombstone is
    /// final and a high-water mark still takes the larger value, whichever side
    /// each came from.
    private static func resolveWithoutAncestor(client: CKRecord,
                                               server: CKRecord) -> CKRecord {
        let type   = server.recordType
        let merged = copy(of: server)    // carries the current change tag
        let keys   = Set(client.allKeys()).union(server.allKeys())

        let clientDate = client["modifiedAt"] as? Date
        let serverDate = server["modifiedAt"] as? Date
        let clientIsNewer: Bool = {
            guard let clientDate else { return false }
            guard let serverDate else { return true }
            return clientDate > serverDate
        }()

        for key in keys {
            let clientValue = client[key]
            let serverValue = server[key]

            // Agreement is never a conflict — see the note in `resolve`.
            if equal(clientValue, serverValue) { continue }

            switch SyncMergePolicy.merge(for: type, field: key) {

            case .tombstone:
                if let winner = firstNonNil(serverValue, clientValue) {
                    merged[key] = winner
                }

            case .maxWins:
                merged[key] = higher(clientValue, serverValue)

            case .immutable:
                // Not a divergence — we simply have no basis to compare. The
                // server's value is the one every device already agrees on.
                continue

            case .lastWriterWins:
                if serverValue == nil {
                    // Only this device has it; nothing to lose by keeping it.
                    merged[key] = clientValue
                } else if clientIsNewer {
                    merged[key] = clientValue
                }
            }
        }

        return merged
    }

    /// Both sides changed the same field since the ancestor.
    private static func resolveContended(policy: FieldMerge,
                                         key: String,
                                         type: CKRecord.RecordType,
                                         client: (any __CKRecordObjCValue)?,
                                         server: (any __CKRecordObjCValue)?) -> (any __CKRecordObjCValue)? {
        switch policy {

        case .maxWins:
            return higher(client, server)

        case .immutable:
            // Two devices disagree about a field that is supposed to be fixed
            // at creation. Keep the server's value so every device converges on
            // the same answer, and surface it — this means something upstream
            // wrote a field it should not have.
            AppLogger.log(tag: "SyncMerge",
                          "Immutable field diverged: \(type).\(key) — keeping server value")
            return server

        case .tombstone:
            // Handled before this call; kept for exhaustiveness.
            return firstNonNil(server, client)

        case .lastWriterWins:
            // A genuine concurrent edit to the same field. The server's value
            // is already durable and every device sees it, so preferring it is
            // deterministic and converges in one round. Preferring the client
            // instead would let two devices ping-pong indefinitely, each
            // overwriting the other on every sync.
            //
            // Client wall-clock is deliberately *not* consulted here: it is the
            // untrustworthy input this whole policy exists to remove, and the
            // only thing it could buy is picking a different arbitrary winner.
            return server
        }
    }

    // MARK: - Value helpers

    /// A copy of the server record, so merging never edits the caller's
    /// instance. The engine caches the *unmerged* server record as the
    /// ancestor for the retry; merging into that same object used to cache the
    /// merged values instead, which made the next conflict misread who had
    /// changed what.
    private static func copy(of record: CKRecord) -> CKRecord {
        (record.copy() as? CKRecord) ?? record
    }

    /// CKRecord values are Objective-C types; compare them the same way
    /// CloudKit does rather than through Swift equality.
    private static func equal(_ lhs: (any __CKRecordObjCValue)?,
                              _ rhs: (any __CKRecordObjCValue)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (l?, r?):
            // CKAsset has no meaningful equality; treat two assets as differing
            // so the field falls through to an explicit policy decision.
            if l is CKAsset || r is CKAsset { return false }
            return (l as AnyObject).isEqual(r as AnyObject)
        }
    }

    private static func firstNonNil(_ values: (any __CKRecordObjCValue)?...) -> (any __CKRecordObjCValue)? {
        values.compactMap { $0 }.first
    }

    /// `max` for the value kinds a high-water mark can be: dates and numbers.
    private static func higher(_ lhs: (any __CKRecordObjCValue)?,
                               _ rhs: (any __CKRecordObjCValue)?) -> (any __CKRecordObjCValue)? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }

        if let l = lhs as? Date, let r = rhs as? Date {
            return (l > r ? l : r) as NSDate
        }
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            return l.compare(r) == .orderedDescending ? l : r
        }
        // Not an orderable kind — fall back to the deterministic choice.
        return rhs
    }
}
