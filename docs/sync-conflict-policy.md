# Sync Conflict Policy

Status: **partly implemented** — §0.1, §0.2, §3.2, §3.3, §3.4, §3.6 and §3.8 have landed. §3.1 is the last outstanding one-way door; the tombstone purge policy in §4 is still unimplemented but is not a schema change
Scope: the CloudKit private-database sync in `Fathom/Data/Sync/`, as part of the
migration from the hand-rolled `SyncEngine` to `CKSyncEngine`.

This document is the contract the merge code is written against. Every record
type gets an explicit policy. "Whatever the engine does by default" is not a
policy.

---

## 0. Two cross-cutting decisions

These apply to every row in the table and are the two most consequential calls
in the document.

### 0.1 Ordering is server-assigned, never client wall-clock

The current engine orders every merge by a client-written `modifiedAt` field:

```swift
if incoming.modifiedAt > existing.modifiedAt { try incoming.update(db) }
```

repeated for all eight synced types in `SyncEngine+Pull.swift`. This is unsafe.
`modifiedAt` is `Date()` on whichever device wrote it, so ordering depends on
two unsynchronised consumer clocks. A device whose clock runs ten minutes fast
wins **every** conflict against the other device for ten minutes, silently, and
a user who manually sets their clock forward can permanently shadow edits made
on their other device. There is no self-correction: the loser's data is
overwritten and gone.

**Decision: order by `CKRecord.modificationDate`, which CloudKit assigns
server-side from a single clock.** Keep the local `modifiedAt` column — it is
still needed to drive the local change-detection queue
(`cloudkit_pending_changes`) — but it stops being the conflict arbiter.

### 0.2 Merge three-way, against the ancestor

`CKSyncEngine` surfaces `.serverRecordChanged` failures carrying **three**
records: the server's current record, our attempted client record, and the
**ancestor** — the common version both sides diverged from. With the ancestor
you can tell "B changed this field" apart from "B never touched this field,"
which is exactly the distinction the current code cannot make.

That gap is why this workaround exists in `apply(changedRecord:)`:

```swift
merged.rating     = incoming.rating     ?? existing.rating
merged.reflection = incoming.reflection ?? existing.reflection
```

with the honest comment that CloudKit "can't distinguish 'cleared' from 'never
set'." The consequence ships today as a permanent bug: **a cleared rating or a
deleted reflection can never propagate.** Coalescing nil to the old value means
erasure is unrepresentable. Three-way merge removes the need for the hack
entirely — if the ancestor had a rating and the client record does not, that is
a deliberate clear, and it wins.

This is the strongest single argument for `CKSyncEngine` over the hand-rolled
engine, ahead of even the retry and backoff handling.

---

## 1. Conflict classes

Six policies. Each row in the table below names one.

| Class | Rule | Converges? |
|---|---|---|
| **Immutable** | Set once at creation, never edited. First write wins; later writes are ignored. | Trivially |
| **LWW-Field** | Per-field last-writer-wins, ordered by server timestamp, three-way merged against the ancestor. | Yes |
| **LWW-Blob** | Whole-value last-writer-wins. Concurrent edits to different parts of the value lose one side. | Yes, lossily |
| **Tombstone-wins** | Soft delete via `deletedAt`. A delete beats a concurrent edit regardless of timestamp. | Yes |
| **2P-Set** | Set membership with add and remove tombstones. Remove is final. | Yes |
| **Per-device counter** | Each device owns a private partition it alone writes; readers sum across partitions. Never merged. | Yes, exactly |

**Per-device counter** deserves a note: it is a G-Counter, the standard CRDT for
additive quantities. Because no device ever writes another device's partition,
there is no conflict to resolve — the merge is a no-op and the total is correct
by construction. It is the right shape for anything that accumulates.

---

## 2. The table

| Record type | User-editable? | Deletes | Class | Notes |
|---|---|---|---|---|
| `Book` — import metadata (`title`, `author`, `format`, `localFilename`, `contentHash`, `importDate`, `language`, `publisher`, `estimated*`) | No | Hard | **Immutable** | Derived from the EPUB at import. Identical on every device by construction; a conflict here means a bug, and should be logged rather than merged. |
| `Book` — user fields (`rating`, `reflection`, `reflectionImageFilename`, `finishedAt`) | Yes | Hard | **LWW-Field** | See §3.1 — recommend splitting into `BookCompletion`. |
| `Book` — `lastReadAt` | Indirectly | Hard | **Max wins** | A high-water mark, not a value. `max(local, remote)`. Never LWW. |
| `Book` — `preprocessingStatus`, `aiEnabled`, `backendBookID` | No | Hard | **Local-only, do not sync** | See §3.2. |
| `BookCategory` (shelves) | Yes | Hard | **LWW-Field** | `name` and `shelfColorHex` are genuine LWW. `sortOrder` is not — see §3.5. |
| `BookCategoryMembership` | Yes | Soft | **2P-Set** | `deletedAt` added in v32; removal is a tombstone, re-adding clears it. See §3.3. |
| `Highlight` | Yes | Soft | **Tombstone-wins** | Delete beats concurrent recolor. `locatorJSON` and `text` are immutable after creation; only `color` and `deletedAt` are mutable. |
| `Note` | Yes | Soft | **Tombstone-wins** | `noteContent` is LWW-Field among the live fields; delete still wins over an edit. |
| `Bookmark` | Yes | Soft | **Tombstone-wins** | Effectively immutable except for `deletedAt` — a bookmark is created or removed, never edited. |
| `SavedWord` | Yes | Soft | **Tombstone-wins** | `pinnedAt` is LWW-Field. `fullDictionaryJSON` is immutable (deterministic lookup result). |
| `ReadingActivity` | No | None | **Per-device counter** | Keyed on `(bookID, date, deviceID)` as of migration v30; totals are `SUM` across devices. See §3.4. |
| `ReadingPosition` | No | None | **LWW-Field + furthest** | `furthestProgression` added; position and progress resolve independently. The backwards-jump prompt is still deferred. See §3.6. |
| `ReaderSettings` | Yes | None | **LWW-Blob** | Accepted tradeoff — see §3.7. |
| `UserProfile` | Yes | None | **LWW-Field** | Three fields (`displayName`, `avatarEmoji`, `avatarColorHex`). Per-field is free here; do it rather than blob. |
| `AIConversation` | n/a | None | **Do not deploy** | See §3.8. |

---

## 3. The rows that need argument

### 3.1 Split `BookCompletion` out of `Book`

`Book` currently mixes two things with opposite semantics: immutable metadata
extracted from the EPUB, and the user's own reflection on having finished it.
Whole-record LWW across that mixture is what forced the nil-coalescing hack.

Recommendation: move `rating`, `reflection`, `reflectionImageFilename`, and
`finishedAt` into a separate `BookCompletion` record keyed by book ID. Then
`Book` becomes genuinely immutable (no merge policy needed at all), and
`BookCompletion` is a small record whose every field is user-authored and
honestly LWW.

This is not required for correctness once three-way merge is in place, but it
makes the invariant structural rather than a rule someone has to remember. It is
also cheap to do now and expensive later: CloudKit production schema is
**additive-only**, so a field you deploy is a field you live with forever.

### 3.2 Stop syncing `preprocessingStatus`, `aiEnabled`, `backendBookID`

`preprocessingStatus` describes work done to a local copy of a file. Syncing it
tells device B that its own copy is `.ready` when B has never processed it —
actively harmful, not merely redundant. `aiEnabled` and `backendBookID` belong
to the dormant AI companion. All three should be local columns that never reach
a `CKRecord`. `aiAnalysisProgress` is already handled this way; extend the same
treatment.

### 3.3 `BookCategoryMembership` needs a tombstone

**Implemented (migration v32).** `deletedAt` added; removal tombstones instead
of deleting, `listMemberships` filters tombstones, and re-adding clears one
rather than being swallowed by the primary key. The table gained an update
trigger — removal is an `UPDATE` now, and without one it would never be queued
at all. The delete trigger stays for genuine hard deletes, since the foreign
keys cascade when a book or shelf is deleted outright. The original argument
follows.

The record has `bookID`, `categoryID`, `addedAt`, `sortOrder`, `modifiedAt` —
**no `deletedAt`** — so removing a book from a shelf relies on a hard CloudKit
delete, handled at `SyncEngine+Pull.swift:390`. That races badly: a hard delete
carries no timestamp to compare against, so a remove on device A concurrent with
any write on device B resolves by arrival order, not intent. The book
reappears on the shelf, or vanishes from it, depending on network timing.

Add `deletedAt` and make this a proper 2P-Set: add and remove are both writes,
remove is final. The composite record name (`"bookID|categoryID"`) is already
correct and should stay — it is what makes the set idempotent.

### 3.4 `ReadingActivity` must be per-device, and `max` is a data-loss bug

**Implemented (migration v30).** The record is keyed on
`(bookID, date, deviceID)`, `DeviceIdentity` supplies the partition, and both
`MemoryGardenViewModel` and `ObservatoryViewModel` already summed by date so
they read correctly unchanged. The original reasoning follows.

The merge this replaced:

```swift
if incoming.duration > existing.duration {
    existing.duration = incoming.duration
    try existing.update(db)
}
```

The comment explains `max` was chosen over `sum` to stay idempotent when the
same record is pulled twice. The reasoning about idempotency is right; the
conclusion is wrong. **Read 20 minutes on iPhone and 15 on iPad on the same day
and the app records 20, not 35.** Every multi-device day under-reports, and it
under-reports silently.

The fix is to stop merging. Key the record on `(bookID, date, deviceID)` instead
of `(bookID, date)`, so each device writes only its own row and never touches
another's. Daily total becomes `SUM(duration) WHERE date = ?`. This is
idempotent (re-pulling overwrites a row with itself), commutative, and
arithmetically correct.

This matters more than its size suggests: the Memory Garden's doodle tiers and
the "forms today, settles tomorrow" reveal are driven by daily duration. Getting
this wrong quietly corrupts the feature the app is built around. Use
`identifierForVendor` for `deviceID`, persisted once — note it changes if the
user deletes and reinstalls the app, which orphans that device's rows as
read-only history. That is acceptable: the totals stay correct, since orphaned
rows are still summed.

Requires a local schema migration to widen the uniqueness constraint from
`(bookID, date)` to `(bookID, date, deviceID)`. Existing rows adopt the current
device's ID.

**Two things surfaced while implementing this**, both pre-existing:

- `logReadingSession` looked its row up with `WHERE bookID = ?` bound to
  `bookID.uuidString`, but GRDB stores `UUID` as a 16-byte blob, so the lookup
  never matched. Every reading session after the first each day tried to
  insert, hit the unique index, threw, and was swallowed by the repository's
  `catch`. **Only the first session per book per day was ever recorded.** The
  same pattern appears in `VocabularyRepositorySQLite.removeSavedWord` and
  `setPinnedAt` — tracked separately.
- **The CDC queue's `recordID` held a raw blob, so nothing could ever upload.**
  The triggers wrote `NEW.id` directly, GRDB encodes `UUID` as 16 bytes, and
  SQLite's TEXT affinity does not convert a blob — so the column read back as
  mojibake or threw. An unparseable local id fails `UUID(uuidString:)`,
  `recordToSave` returns nil, and CKSyncEngine drops the change. It failed
  closed, so no junk reached CloudKit, but no local change reached it either.
  Migration v31 formats the id as canonical UUID text in the trigger (with a
  `typeof()` guard for ids already stored as text) and rebuilds the queue.
  The composite membership key also moved from `|` to `_` there; the triggers
  had kept emitting `|` after `CKRecordName` switched.
- **The CDC triggers are incompatible with `UPSERT` on synced tables.** A
  statement carrying its own `ON CONFLICT` clause overrides the conflict
  resolution inside any trigger it fires, downgrading the trigger's
  `INSERT OR REPLACE INTO cloudkit_pending_changes` to a plain `INSERT`, which
  then fails against that table's primary key. Anything writing to a synced
  table must use fetch-then-write, not upsert. `dbQueue.write` serialises
  writers, so that is atomic regardless.

### 3.5 `sortOrder` — accept the flaw for v1, knowingly

Integer `sortOrder` under concurrent reordering does not converge. Two devices
reordering shelves independently produce interleaved or duplicate orders, and
per-field LWW on an integer cannot fix it — the values are individually valid
and jointly meaningless.

The correct solution is fractional indexing: a string key between neighbours, so
an insert never renumbers anything and concurrent inserts converge to a
deterministic order. Real, but it is a schema change plus a UI-layer change for
a failure mode that requires reordering shelves on two devices at once, which
produces cosmetic disorder rather than data loss.

**Recommendation: ship integer `sortOrder` with per-field LWW for v1, and record
here that it is a known non-converging field.** Revisit if anyone reports it.
This is the one place in this document where the cheap answer is the right one,
and it is deliberate rather than accidental.

### 3.6 `ReadingPosition` — separate "where I am" from "how far I got"

**Field implemented.** `ReadingState` now carries `locatorJSON`, `savedAt` and
`furthestProgression` in one record, and `ReadingStateStore.applyRemoteState`
resolves the two halves independently: the position is last-write-wins, while
the high-water mark is taken whenever it is larger — *including when the
position it arrived with lost*. A device that read ahead and was then
superseded still contributes the fact that the reader got that far.

The **backwards-jump prompt remains deferred**, as this section always
allowed — the data it needs is now being recorded, which was the part that
could not be added later.

The original argument follows. Position was LWW on a client-written `savedAt`.
Two problems.

First, per §0.1, the clock is untrustworthy. Use the server timestamp.

Second, and more interesting: LWW is not obviously what a reader wants. Read
ahead on iPad, then open the iPhone — LWW jumps you forward to the iPad
position, which is usually right. But it is also how readers lose their place
when a device syncs a position they did not intend, and there is no way back.

Established behaviour here (Kindle, Books) is to keep both: a current position
that is LWW, and a separate furthest-progress high-water mark. When the incoming
position is *behind* local progress by a meaningful margin, prompt — "Continue
from the furthest page read?" — rather than silently moving the reader.

**Recommendation: add `furthestProgression` (max-wins) alongside the LWW
current position. Prompt on a backwards jump greater than one chapter.** The
prompt can be deferred past v1; the field cannot, because backfilling a
high-water mark you never recorded is impossible.

One implementation note: Readium's `currentLocation` is debounced and is stale
immediately after a page turn. Push position from `locationDidChange`, not from
a read of `currentLocation` at push time, or the synced position lags by a page.

### 3.7 `ReaderSettings` — LWW-Blob is fine, and here is why

The settings record is a single encoded JSON blob with one timestamp, so
changing font size on one device clobbers a concurrent theme change on the
other. Per-field would be strictly better.

I recommend keeping the blob anyway. Reader settings are adjusted rarely, almost
always on the device in the user's hand, and losing one of two concurrent
settings edits costs a re-tap rather than data. Field-splitting a `Codable`
struct into individual `CKRecord` fields also couples the schema to the struct's
shape — and since CloudKit schema is additive-only, every future settings field
becomes a permanent schema entry. The blob keeps that surface at one field.

This is a real tradeoff being taken deliberately, not an oversight.

### 3.8 Do not deploy `AIConversation` to the production schema

The AI companion is behind `FeatureFlags.aiCompanionEnabled = false`, and the
pull path carries a comment noting it is broken as written — it inserts
`paragraphID 0`, violating the NOT NULL foreign key, so `INSERT OR IGNORE`
silently drops the row.

**CloudKit production schema cannot be reduced.** A record type deployed to
production can never be removed and its fields can never be retyped. Deploying
a record type that is known to be wrong, for a feature that is switched off,
permanently locks in a schema nobody has validated.

Keep the type in the development environment. Exclude it from the production
schema until the feature is real and its shape is settled.

---

## 4. Delete semantics, stated once

- **Annotations** (`Highlight`, `Note`, `Bookmark`, `SavedWord`) soft-delete via
  `deletedAt`. Correct: a hard delete carries no evidence it happened, so a
  device that was offline during the delete cannot distinguish "deleted
  remotely" from "not yet synced" and will resurrect the row.
- **Delete beats edit.** A tombstone wins over a concurrent edit regardless of
  which timestamp is later. Undelete, if it ever exists, must be an explicit
  user action that clears `deletedAt` — never an implicit consequence of merge
  ordering.
- **Tombstones need a purge policy.** They currently accumulate without bound.
  Proposal: purge locally after 90 days, and never purge a tombstone newer than
  the oldest device's last successful sync. Ninety days is comfortably longer
  than any plausible offline period.
- **`Book` deletion stays hard**, because it also removes a file from the
  ubiquity container. Order matters: confirm the CloudKit record deletion
  first, then remove the file. Reversing that orphans the file if the record
  delete fails.

---

## 5. What is out of scope here

`Book.localFilename` points at an EPUB in the iCloud Documents container, which
syncs through a **different mechanism** than CloudKit records — `ICloudFileStore`
and `ICloudDownloadMonitor`, not `CKRecord`. A record can therefore arrive
before its file exists locally. That is a real consistency problem with its own
state machine ("record present, file not yet downloaded"), and it deserves its
own document rather than a row in this table.

---

## 6. Summary of changes this policy implies

| # | Change | Why |
|---|---|---|
| 1 | Order merges by `CKRecord.modificationDate`, not client `modifiedAt` | Client clocks are not trustworthy (§0.1) |
| 2 | Three-way merge against the ancestor record | Makes field clears representable; removes the nil-coalesce hack (§0.2) |
| 3 | ~~Add `deletedAt` to `BookCategoryMembership`~~ **done, v32** | Shelf removals currently race (§3.3) |
| 4 | ~~Re-key `ReadingActivity` on `(bookID, date, deviceID)`, sum at read~~ **done, v30** | `max` under-reports every multi-device day (§3.4) |
| 5 | ~~Add `furthestProgression` to `ReadingPosition`~~ **done** | Cannot be backfilled later (§3.6) |
| 6 | Stop syncing `preprocessingStatus`, `aiEnabled`, `backendBookID` | Describes local state; syncing it is actively wrong (§3.2) |
| 7 | Split `BookCompletion` out of `Book` | Makes the immutable/mutable split structural (§3.1) |
| 8 | Exclude `AIConversation` from the production schema | Additive-only schema; do not lock in a known-broken type (§3.8) |
| 9 | Tombstone purge policy | Unbounded growth (§4) |

Items 1–6 and 8 have landed. **Item 7 is the last remaining one-way door** and
must be settled before the first production schema deployment — CloudKit's
production schema is additive-only.

**Item 9 has not been implemented.** An earlier revision of this document said
it had; that was wrong. Tombstones — on annotations since v19, and now on shelf
memberships too — still accumulate without bound. It is not a schema change and
so does not block deployment, but it does need doing.

One further change landed with §3.6 that this table did not anticipate:
`savedAt` used to live in `UserDefaults` while the locator lived in a JSON
file, so a crash between the two writes left a position stamped with the wrong
time — and that timestamp decided sync conflicts. All three fields now live in
one atomically-replaced file, with the legacy shape upgraded on first read.
