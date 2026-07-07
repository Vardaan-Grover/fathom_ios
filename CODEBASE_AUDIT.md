# Fathom iOS — Codebase Audit

Audit date: 2026-07-08. Scope: all ~150 Swift files (~30k lines) across App, Data, Domain, Presentation, ReaderEngine, ContextEngine, and UI layers. No changes were made — this is a findings report only.

Severity legend: 🔴 Critical (data loss / broken feature) · 🟠 High (real bug or major perf cost) · 🟡 Medium (bad practice, latent bug) · ⚪ Low (hygiene / cleanup)

## Progress log

**Policy decision (2026-07-08):** AI Companion features stay in the codebase but are not user-facing. UI entry points remain commented out; background paths are gated behind `FeatureFlags.aiCompanionEnabled` (`Fathom/App/FeatureFlags.swift`, currently `false`).

**Phase 1 — done (2026-07-08):**
- ✅ 1.1 Resolved as dormant: migration `v26_disable_ai_conversation_sync` drops the AI CDC triggers and purges queued rows; push/pull branches are flag-gated. The paragraphID-0 FK bug is documented inline and must be fixed before re-enabling the feature.
- ✅ 1.2 Fixed: `Book.toCKRecord/from` now round-trip rating/reflection/reflectionImageFilename/finishedAt; the pull handler merges instead of blind-overwriting, so nil incoming values (old-format records) and local-only `aiAnalysisProgress` are preserved.
- ✅ 1.4 Fixed: reading position/settings/profile pushes use `CKModifyRecordsOperation` with `.changedKeys` (`SyncEngine.saveOverwriting`) instead of `CKDatabase.save`.
- ✅ 2.1 Fixed: `AppLogger` redacts Authorization/apikey headers and is compiled off in release builds.
- ✅ 1.8 Mitigated: backend ingestion polling is flag-gated off while AI is dormant (timeout/backoff still needed when re-enabled).

**Phase 2 — done (2026-07-08):**
- ✅ 1.3 Fixed: ReadingActivity now has a full sync path (`CKRecordType.readingActivity`, `toCKRecord/from`, push branch, pull branch). Pull merges same-(bookID, date) rows from other devices via `max(duration)` — idempotent, honors the unique index. Rows stuck in the queue on existing installs get pushed and cleared on the next flush.
- ✅ 1.5 Fixed: new `StableHash` (FNV-1a) replaces seeded `hashValue` at all 7 palette sites (HomeViewModel, VocabularyTabView ×2, AddWordSheet, CollectionsListView ×2, coverColorPair) — colors are stable across launches now.
- ✅ 1.7 Fixed: migration `v27_millisecond_queue_timestamps` recreates CDC triggers with millisecond `queuedAt`; `clearQueue` is awaited and matches on `(recordType, recordID, queuedAt)` so mid-push edits survive cleanup; `scheduleFlush` loops until a pass makes no progress, catching changes whose observation fired during a flush.
- ✅ 1.9 Fixed: `BookPreprocessingCoordinator` keeps an in-flight book-ID set; duplicate `preprocess` calls are skipped.
- ✅ 1.10 Fixed: reading timer pauses on scenePhase inactive/background; minimum logged session is 60 s (per the original code comment's production intent — adjust `ReaderScreen.minimumLoggedSession` if desired).
- ✅ 1.11 Fixed: LIKE wildcards escaped (`ESCAPE '\'`) in all four paragraph-search queries.
- ✅ 1.12 Fixed: a pending import continuation is cancelled (resumed with `CancellationError`) before a new one is stored.
- ⏭️ 1.6 Skipped (AI dormant): resumed-thread history fix deferred until the AI Companion ships; noted inline where relevant.

---

## 1. Critical correctness bugs

### 1.1 🔴 AI chat sync is wired to a table nothing writes to
The chat feature reads/writes `ai_threads.json` via `AIThreadStore` (`Fathom/Data/AIThreadStore.swift`, used by `AICompanionScreen.swift` and `AIChatsListScreen.swift`). The entire CloudKit sync path for conversations — the `aiConversations`/`aiMessages` tables, the CDC triggers in `DatabaseManager.swift` (v21), the push helpers in `SyncEngine.swift:481-534`, and the pull handler in `SyncEngine+Pull.swift:225-265` — operates on SQLite tables that **no feature code ever writes to**. Net effect: AI conversations never sync, and the sync code is exercising a dead store.

Worse, the pull handler inserts pulled conversations with `paragraphID: 0`. That column has a NOT NULL FK to `paragraphs(id)`; row id 0 never exists, so with `foreignKeysEnabled` the `INSERT OR IGNORE` silently drops every pulled conversation.

### 1.2 🔴 Syncing a Book record wipes local completion data
`Book.toCKRecord`/`from(ckRecord:)` (`Fathom/Data/Sync/CloudKitRecordTypes.swift:34-93`) omit `rating`, `reflection`, `reflectionImageFilename`, `finishedAt`, and `aiAnalysisProgress`. On pull, `SyncEngine+Pull.swift:123-134` does `incoming.update(db)`, which rewrites **every column** of the local row. Any remote Book change (e.g. `lastReadAt` touched on another device — or even this device's own record echoed back) will null out the user's rating, reflection, reflection image, and finished date. This is user-visible data loss.

### 1.3 🔴 ReadingActivity changes are queued for sync but can never be pushed
`DatabaseManager.swift` v21 creates CDC triggers for `readingActivity` (record type `'ReadingActivity'`) and seeds the queue with existing rows. But `CKRecordType` has no `readingActivity` case, `buildRecords` (`SyncEngine.swift:323-362`) has no branch for it, and there is no `toCKRecord` for the model. These rows sit in `cloudkit_pending_changes` forever, get re-read on every flush, and reading stats never sync.

### 1.4 🔴 Reading position / settings / profile pushes fail after the first save
`pushReadingPosition`, `pushReaderSettings`, `pushUserProfile` (`SyncEngine.swift:116-178`) build a **fresh** `CKRecord` each time and call `database.save(r)`. The async `save` uses the default `.ifServerRecordUnchanged` policy; a fresh record has no change tag, so once the record exists on the server every subsequent save fails with `serverRecordChanged`. Cross-device reading-position sync effectively works exactly once per record. (The main `flush()` path avoids this by using `CKModifyRecordsOperation` with `.changedKeys` — these three paths need the same treatment.)

### 1.5 🔴 Book/word accent colors are not stable across launches
`HomeViewModel.paletteIndex` (`Fathom/Presentation/HomeViewModel.swift:318`) uses `abs(book.id.hashValue)` and the comment claims "same book always gets the same color across app launches." Swift's `Hashable` is seeded per-process, so `hashValue` for the same UUID **changes every launch** — every cover color reshuffles on restart. Same bug in `VocabularyTabView.swift:29,37` (`word.word.hashValue`). Fix: derive the index from stable bytes (e.g. `id.uuid` bytes or a UTF-8 checksum).

### 1.6 🟠 Resumed AI chats send no conversation history to the backend
`AICompanionViewModel` (`Fathom/UI/AICompanionScreen.swift:26-42`) loads a persisted thread's messages for display, but `conversationHistory` starts empty and is only appended during the live session. Reopening a thread and asking a follow-up sends the backend zero context — the AI "forgets" the whole prior conversation.

### 1.7 🟠 Sync queue race can drop changes made during a flush
`clearQueue` (`SyncEngine.swift:366-385`) deletes processed rows by `(recordType, recordID)` only, in a detached `Task`. If the user edits a record *while* it's being pushed, the trigger re-queues it (same key, newer `queuedAt`), and `clearQueue` then deletes the re-queued row — the newer change is silently unsynced until some later edit. Relatedly, `scheduleFlush`'s `isPushing` guard drops observation fires that arrive mid-flush; the comment claims the observation "will fire again," but ValueObservation only fires on *changes*, so a change landing mid-flush may wait indefinitely.

### 1.8 🟠 Backend polling loop can run forever
`waitForBackendReady` (`Fathom/ContextEngine/BookPreprocessingCoordinator.swift:81-97`) polls every 3 s with no timeout, no max attempts, no backoff, and no `Task.isCancelled` check. If the backend hangs in `processing`, the app polls the network forever and the book stays `.inProgress` permanently.

### 1.9 🟠 Duplicate concurrent preprocessing of the same book
`resumePreprocessingIfNeeded` (`Fathom/Presentation/LibraryViewModel.swift:43-52`) fires a detached `preprocess(book:)` for every book without paragraphs on **every** `load()`, with no in-flight tracking. Two `load()` calls (or a load during a slow preprocess) run the same book through extraction twice, inserting duplicate chapters/paragraphs (the `paragraphs` unique key on `(bookID, absoluteIndex)` will make the second run's inserts fail mid-chapter and mark the book `.failed`).

### 1.10 🟠 Reading-session timer counts backgrounded time, and ships a test value
`ReaderScreen` (`Fathom/UI/ReaderScreen.swift:254-267`) measures `onAppear`→`onDisappear` wall time. Locking the phone or switching apps for an hour with the reader open logs an hour of "reading." The threshold also carries `// Changed to 10s for easier testing, maybe 60s in production`. Session data also silently dies if the app is terminated (onDisappear never runs).

### 1.11 🟡 LIKE-pattern injection in paragraph matching
`NarrativeContextStore.chapterRestrictedSearch` interpolates the selected text into a `LIKE '%…%'` pattern without escaping `%`/`_` (`Fathom/Data/NarrativeContextStore.swift:134-138`). Not a SQL injection (parameterized), but selections containing `%` or `_` match wrongly, so AI context resolution silently degrades.

### 1.12 🟡 Second import while one is pending leaks a continuation
`LibraryViewModel.importContinuation` is a single slot. Starting a new import while the customization sheet is up overwrites the stored continuation without resuming it — a `CheckedContinuation` leak (runtime warning, hung task).

### 1.13 🟡 Shipped migrations were edited after release
`v20_add_modified_at` stamps `readingActivity` triggers, but `readingActivity` is created in `v24`, which is *registered before* v19–21 in `makeMigrator()` (`DatabaseManager.swift:330-360` vs `367+`). It happens to work because registration order = execution order on fresh installs, and old installs already ran v20 before it mentioned readingActivity — but it means the same migration name has shipped with different bodies, and any future reorder breaks it. Also `v25` uses `defaults(to: Date())`, which freezes the *migration run time* as the column default forever.

---

## 2. Security

### 2.1 🔴 Bearer tokens and full payloads printed to console in release builds
`AppLogger.logNetworkRequest` (`Fathom/Data/AppLogger.swift:12-24`) prints **all headers including `Authorization: Bearer <JWT>`** plus full request/response bodies, via `print`, with `isEnabled = true` unconditionally. Console logs are captured in sysdiagnoses and visible to any connected Mac. Should be `os.Logger` with `.private` redaction, header allowlisting, and disabled in release.

### 2.2 🟠 Hardcoded backend: plain-HTTP LAN IP
`BackendService.baseURL = http://192.168.29.216:8080` (`Fathom/Data/BackendService.swift:62-64`). Dev-machine IP baked into source, no TLS, no environment switching — and no ATS exception exists in Info.plist/pbxproj, so on-device builds should be failing ATS anyway. Needs a configuration layer (xcconfig / build settings / plist).

### 2.3 🟡 Supabase config hardcoded; implicit OAuth flow
`AuthService.swift:7-18` hardcodes the project URL + anon key (anon keys are semi-public, but config belongs in build settings) and uses `flowType: .implicit` — Supabase recommends PKCE for mobile.

### 2.4 🟡 No entitlements file in the project
No `.entitlements` file and no `CODE_SIGN_ENTITLEMENTS` in the pbxproj — yet the app depends on CloudKit (`iCloud.com.Vardaan.Fathom`), iCloud Documents, and silent push. All that code can only ever hit its "iCloud unavailable" fallback paths as currently configured. Worth confirming whether sync has ever run outside the simulator.

---

## 3. Performance

### 3.1 🟠 Every page turn: full JSON file rewrite + CloudKit network push
`ReaderScreen.onLocationChange` → `ReadingStateStore.saveLocator` (`Fathom/Data/ReadingStateStore.swift:40-58`) loads the *entire* locator dictionary from disk, decodes, mutates, re-encodes, and rewrites it **synchronously on the main thread, on every page flip** — then posts a notification that makes `SyncEngine.pushReadingPosition` do a CloudKit round-trip per flip (which also fails, see 1.4). Needs debouncing (e.g. save at most every few seconds / on reader exit) and an in-memory cache. `ReadingStateStore` is also accessed from both the main thread and the SyncEngine actor with zero synchronization.

### 3.2 🟠 Repository anti-pattern: actors blocking on sync GRDB inside pointless continuations
`BookRepositorySQLite` and `VocabularyRepositorySQLite` wrap *synchronous* `dbQueue.read/write` in `withCheckedContinuation`. The continuation adds nothing (everything resolves synchronously), and the blocking DB call runs on the cooperative thread pool — exactly what Swift concurrency forbids. GRDB has native async APIs (`try await dbQueue.read { }`), already used correctly in `NarrativeContextStore` and `BookPreprocessingCoordinator`.

### 3.3 🟠 Synchronous DB I/O on the main thread throughout the stores
`NoteStore`, `HighlightStore`, `BookmarkStore` do blocking `dbQueue.read/write` and are called directly from UI code (`ReadiumNavigatorView` menu actions, `ReaderScreen`, list views, `ProfileSharedComponents`, `ExportDataScreen`, `StorageUsageScreen`). Same for `AIThreadStore`, which decodes and re-encodes the **entire** threads JSON file on every message append.

### 3.4 🟠 Vocabulary search decodes JSON blobs per keystroke
`VocabularyTabViewModel.filteredWords` (`Fathom/Presentation/VocabularyTabViewModel.swift:93-115`) is a computed property that `JSONDecoder`-decodes every word's `fullDictionaryJSON` for the definition-text match — on every access, and it's accessed several times per render (`masonryGrid`, `wordCount`, `canStudy`, `expandedHasNext`…), on every keystroke. Decode once into a cache keyed by word id, and memoize the filtered array.

### 3.5 🟠 `updateUIViewController` re-submits preferences and re-reads notes on every SwiftUI update
`ReadiumNavigatorView.updateUIViewController` (`ReadiumNavigatorView.swift:727-757`) fires a `Task { navigator.submitPreferences(…) }`, re-applies the AI highlight, and re-fetches + re-applies all note decorations (sync DB read) each time SwiftUI re-evaluates the reader — which happens on every page indicator change, bar toggle, etc. Should diff settings/notesVersion and only act on change.

### 3.6 🟡 Debug instrumentation running in production queries
`NarrativeContextStore.chapterRestrictedSearch` executes 5+ extra diagnostic SQL queries (global LIKE count, sample rows, hex dumps) guarded only by `AppLogger.isEnabled`, which is always true. Also `paragraphs.text LIKE '%probe%'` is an unindexed full scan over what can be tens of thousands of rows — SQLite FTS5 would make this cheap.

### 3.7 🟡 Whole-file memory spikes on import/upload
`LibraryViewModel.importBook` reads the entire EPUB into `Data` to hash it; `BackendService.uploadEPUB` reads the file into memory again and uses `upload(for:from:)`. Use streaming SHA-256 (`SHA256` update over chunks) and `URLSession.upload(for:fromFile:)`.

### 3.8 🟡 `chapterTitle` recomputed from scratch constantly
`ReaderScreen.chapterTitle` and `ScrubPreviewPopover.chapterTitle` rebuild the flattened TOC → positions marker table (O(TOC × positions) with string splitting) on every evaluation. Compute the marker table once when TOC/positions load.

### 3.9 🟡 File-system checks in model computed properties
`Book.localURL`/`coverURL` → `ICloudFileStore.bookURL` do `FileManager.fileExists` (disk I/O) and are called during view rendering (e.g. `HomeScreen`, `RecentlyReadTile`).

### 3.10 ⚪ Misc
- `DatabaseQueue` rather than `DatabasePool` + WAL: every read blocks writes; the paragraph indexer writes large batches while the reader queries context.
- `DateFormatter` allocated per call in `logReadingSession`, `ObservatoryViewModel.refresh`, etc.
- `CKContainer(identifier:)` re-created on every `container` access in `SyncEngine`.
- Sequential per-record `dbQueue.write` transactions when applying a pull batch (`SyncEngine+Pull.swift:101-106`) — batch them.

---

## 4. Memory

- 🟡 The import path (3.7) is the biggest transient spike: an 80 MB EPUB costs ~160 MB+ during import.
- ⚪ Readium preload counts were already trimmed to fight jetsam (`ReadiumNavigatorView.swift:629-641`) — good; the cover `NSCache` in `BookFileStore` is also right.
- ⚪ `Fathom-Run.trace` (4.0 GB) and `.build/` live in the working tree. Both are gitignored but eat disk and slow Spotlight/backups; the `.gitignore` still references the old "Readora" project name paths.

---

## 5. Architecture & consistency

### 5.1 🟠 Two competing persistence/DI worlds
- Injected via `AppContainer`: `BookRepository`, `CategoryRepository`, `VocabularyRepository`, `ContextEngine`, `AIClient`.
- Singletons reached from anywhere: `NoteStore`, `HighlightStore`, `BookmarkStore`, `AIThreadStore`, `ReadingStateStore`, `ReaderSettingsStore`, `UserProfileStore`, `BackendService`, `SyncEngine`, `NarrativeContextStore`, `VocabularyService`, `ICloudFileStore`, `DatabaseManager`.

The split has already caused bugs (1.1) and duplication — e.g. `ReaderScreen.swift:195` constructs a brand-new `VocabularyRepositorySQLite` inline instead of using the injected one. Pick one direction (realistically: keep pragmatic singletons but route them all through `AppContainer` so they're swappable and the object graph is visible).

### 5.2 🟠 Storage split across four mechanisms with no clear rule
SQLite (books, annotations, vocab, paragraphs), JSON files (reading state, reader settings, profile, AI threads), UserDefaults (savedAt timestamps, My Library ordering, migration flags, CK tokens), and CloudKit. AI threads being JSON while their sync path expects SQLite is the direct cause of 1.1. Reading position modifiedAt living in UserDefaults while the locator lives in JSON is a consistency hazard (two writes, no atomicity).

### 5.3 🟡 Notification-name spaghetti for cross-feature flows
23 `onReceive`/publisher sites; flows like vocab→book jump chain `.vocabularyJumpToBook` → tab switch → `Task.sleep(300ms)` → `.homeScreenOpenReader` (`RootView.swift:165-177`). Sleep-based sequencing is fragile; a small router/coordinator would remove the races. Similar `Task.sleep(500ms)` choreography is sprinkled through `HomeScreen` context-menu handlers.

### 5.4 🟡 `HomeViewModel` defaults to `InMemoryCategoryRepository()`
`init(bookRepository:categoryRepository: CategoryRepository = InMemoryCategoryRepository())` — forgetting the argument at any call site silently discards user shelves. Remove the default.

### 5.5 🟡 Error swallowing as the house style
Dozens of `try?` and `catch { return [] }` sites: `listBooks` returns `[]` on DB error with no log; every store logs-and-continues; `SyncEngine.removeFromQueue` is `try?`; `ReadingStateStore`/`ReaderSettingsStore` saves are `try?` (a failed settings save is silently lost). At minimum, log every swallowed error; for user-initiated writes, surface failure.

### 5.6 🟡 Crash-on-init patterns
`try!` in `ReadingStateStore`, `ReaderSettingsStore`, `UserProfileStore`, `JSONBookRepository` initializers, `fatalError` in `DatabaseManager.shared` — a full disk or sandbox hiccup at launch is an instant crash with no recovery UI.

### 5.7 🟡 Sendability / isolation debt
Swift 5 language mode, no strict concurrency. `ReadiumStack` is `@MainActor` yet `@unchecked Sendable`; `ICloudFileStore` mutable state is touched from the auth listener, SyncEngine actor, and main thread with a comment asserting single-queue access that nothing enforces; `AuthService` mutates `@Published` from a non-`@MainActor` class; `AppLogger.isEnabled` is `nonisolated(unsafe)`. Fine today, but these will all bite when you enable Swift 6 mode.

---

## 6. Dead code & vestigial layers

- ⚪ **Entire on-device LLM preprocessing pipeline is unused** (~1,200 lines): `PreprocessingLLMClient` (Gemini calls; nothing ever instantiates it), `ChunkBuilder`, `EntityReconciler`, `EntitySanitizer`, `EventSanitizer`. The DB tables `entities`, `entityMentions`, `scenes`, `events` are written by nothing.
- ⚪ `ReaderService`/`DefaultReaderService.openSamplePassage` returns hardcoded placeholder text; `LibraryViewModel.openBook` and `ReaderViewModel` (the whole file) are only reachable through it; `MockAIClient`/`AIClient.explainPassage`/`ContextEngine.makeBundle` feed the same vestigial path. The real reader flow goes through `ReaderScreen` + `BackendService` directly.
- ⚪ `EPUBReaderView.swift` is 100% commented out — delete.
- ⚪ `JSONBookRepository` superseded by SQLite; `InMemoryBookRepository`'s "Demo Book" ships in the app target.
- ⚪ The disabled "Ask AI" menu block in `ReadiumNavigatorView.swift:186-198` is commented-out code kept "in case."
- ⚪ `Sources/GRDBTest/main.swift` — a stray SwiftPM executable target in the app repo.
- ⚪ Four icon sets (`FathomIcon` … `FathomIcon4`) plus `Fathom-Icon.icon` at various paths.

---

## 7. Testing & tooling

- 🔴 **There is no test target.** Zero unit tests for the migration chain, sync conflict logic (LWW), paragraph indexing, import branching (flows A/B, duplicate branches), or study-question building — all of which are pure-logic and eminently testable. This is the single highest-leverage structural investment available.
- ⚪ No SwiftLint/SwiftFormat config; formatting drifts (mixed 2/4-space files, trailing-comma styles).
- ⚪ `IPHONEOS_DEPLOYMENT_TARGET = 18.6` with `#available(iOS 26, *)` glass-effect branches and an `#available(iOS 18.0, *)` check that is always true — the iOS 18 branch in `AICompanionScreen.swift:382-405` can be flattened.

---

## Suggested attack order

| Phase | Items | Why first |
|---|---|---|
| 1. Stop the bleeding | 1.2 (Book pull wipes completion data), 2.1 (token logging), 1.4 (position push broken), 1.1 decision (pick JSON *or* SQLite for AI threads) | Data loss + credential exposure |
| 2. Correctness | 1.3, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11 | User-visible bugs, cheap fixes |
| 3. Performance | 3.1 (page-turn I/O), 3.2/3.3 (DB access model), 3.4, 3.5 | Directly felt in reading & vocab UX |
| 4. Structure | 5.1/5.2 (DI + storage unification), 5.5/5.6 (error handling), config layer for 2.2/2.3 | Enables everything after |
| 5. Hygiene | Section 6 deletions, test target bootstrap (7), lint config | Lowers ongoing cost |
