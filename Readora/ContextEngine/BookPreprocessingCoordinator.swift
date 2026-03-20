import Foundation
import GRDB
import ReadiumShared
import ReadiumStreamer

actor BookPreprocessingCoordinator {
    private let previewChunkCount = 3
    private let dbQueue: DatabaseQueue

    private let llmClient = PreprocessingLLMClient("")

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Starts the preprocessing pipeline for a book
    func preprocess(book: Book) async {
        do {
            print("▶️ Started Preprocessing for book: \(book.title)")

            // 1. Update status to inProgress
            var processingBook = book
            processingBook.preprocessingStatus = .inProgress
            processingBook.aiAnalysisProgress = 0.01  // Start progress
            try await saveBookStatus(processingBook)

            // 2. Open Publication using Readium
            guard let localURL = book.localURL else {
                throw PreprocessingError.invalidURL
            }

            guard let fileURL = FileURL(url: localURL) else {
                throw PreprocessingError.invalidURL
            }

            let stack = await ReadiumStack.shared

            let retrieveResult = await stack.assetRetriever.retrieve(url: fileURL)
            guard case .success(let asset) = retrieveResult else {
                throw PreprocessingError.publicationOpenFailed
            }

            let opener = await stack.publicationOpener
            let openResult = await opener.open(
                asset: asset, allowUserInteraction: false, sender: nil)
            guard case .success(let publication) = openResult else {
                throw PreprocessingError.publicationOpenFailed
            }

            print("✅ EPUB Opened: \(publication.metadata.title ?? "Unknown")")
            processingBook.aiAnalysisProgress = 0.05
            try await saveBookStatus(processingBook)

            // 3. Iterate through Reading Order and Extract Paragraphs
            try await extractAndSaveParagraphs(from: publication, bookID: book.id)
            print("✅ Paragraph extraction complete!")
            processingBook.aiAnalysisProgress = 0.05
            try await saveBookStatus(processingBook)

            try await linkChapterBoundaries(bookID: book.id)

            // 4. Build Chunks
            let chunks = try await buildAndLogChunks(bookID: book.id)
            print("✅ Chunking complete — \(chunks.count) chunks built.")
            processingBook.aiAnalysisProgress = 0.10
            processingBook.preprocessingStatus = .completed
            try await saveBookStatus(processingBook)
            
            // 5. Extract Entities
            processingBook.aiAnalysisProgress = 0.15
            try await saveBookStatus(processingBook)

            try await runEntityExtraction(bookID: book.id, chunks: chunks)

            try await reconcileEntities(bookID: book.id)

            processingBook.aiAnalysisProgress = 0.30
            try await saveBookStatus(processingBook)
        } catch {
            print("❌ Preprocessing failed: \(error)")
            var failedBook = book
            failedBook.preprocessingStatus = .failed
            try? await saveBookStatus(failedBook)
        }
    }

    private func runEntityExtraction(bookID: UUID, chunks: [ParagraphChunk]) async throws {
        // Build a lookup dictionary: absoluteIndex → NarrativeParagraph
        // This lets EntitySanitizer quickly find the paragraph text for any mention
        // without going back to the database.
        // We include BOTH prefix and main paragraphs from ALL chunks (not just the preview ones),
        // because a mention in chunk 2 might reference a prefix paragraph from chunk 1.

        var paragraphsByIndex: [Int: NarrativeParagraph] = [:]

        for chunk in chunks {
            for p in chunk.paragraphs {
                paragraphsByIndex[p.absoluteIndex] = p
            }
        }

        let chunksToProcess = Array(chunks.prefix(previewChunkCount))

        for (i, chunk) in chunksToProcess.enumerated() {
            // Capture actor properties as locals before entering concurrent context
            let client = llmClient
            let db = dbQueue
            let localParagraphsByIndex = paragraphsByIndex  // already a local, just for clarity
            let batchSize = 3
            var batchStart = 0
            while batchStart < chunksToProcess.count {
                let batchEnd = min(batchStart + batchSize, chunksToProcess.count)
                let batch = Array(chunksToProcess[batchStart..<batchEnd])
                await withTaskGroup(of: Void.self) { group in
                    for (offset, chunk) in batch.enumerated() {
                        let i = batchStart + offset
                        group.addTask {
                            await self.processChunk(
                                chunk: chunk,
                                index: i,
                                bookID: bookID,
                                client: client,
                                db: db,
                                paragraphsByIndex: localParagraphsByIndex
                            )
                        }
                    }
                }
                batchStart = batchEnd
            }
        }
    }

    private nonisolated func processChunk(
        chunk: ParagraphChunk,
        index: Int,
        bookID: UUID,
        client: PreprocessingLLMClient,
        db: DatabaseQueue,
        paragraphsByIndex: [Int: NarrativeParagraph]
    ) async {
        do {
            print("🔍 Extracting entities for chunk \(index)...")

            // Retry-based LLM call
            var lastError: Error?
            var rawResponse: EntityExtractionResponse?
            for attempt in 0..<3 {
                do {
                    rawResponse = try await client.extractEntities(chunk: chunk)
                    break
                } catch {
                    lastError = error
                    if attempt < 2 {
                        let wait = UInt64(pow(2.0, Double(attempt + 1)))
                        print("⏳ Chunk \(index) retry \(attempt + 1) in \(wait)s...")
                        try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                    }
                }
            }

            guard let response = rawResponse else {
                print(
                    "⚠️ Chunk \(index) failed after retries: \(lastError?.localizedDescription ?? "unknown")"
                )
                return
            }

            let cleanedEntities = EntitySanitizer.sanitize(
                entities: response.entities,
                paragraphsByIndex: paragraphsByIndex
            )

            for entity in cleanedEntities {
                let aliasesData = try JSONEncoder().encode(entity.aliases)
                let aliasesJSON = String(data: aliasesData, encoding: .utf8) ?? "[]"

                let savedEntity = NarrativeEntity(
                    id: UUID(),
                    bookID: bookID,
                    canonicalName: entity.name,
                    type: entity.type,
                    aliasesJSON: aliasesJSON,
                    description: nil,
                    importanceScore: Double(entity.paragraphMentions.count),
                    firstMentionParagraphID: nil,
                    lastMentionParagraphID: nil
                )

                var mentions: [NarrativeEntityMention] = []
                for mention in entity.paragraphMentions {
                    guard let paragraph = paragraphsByIndex[mention.absoluteIndex],
                        let paragraphID = paragraph.id
                    else { continue }

                    let offsets = EntitySanitizer.resolveOffsets(
                        for: mention.surfaceForm, in: paragraph.text)
                    for (charStart, charEnd) in offsets {
                        mentions.append(
                            NarrativeEntityMention(
                                id: UUID(),
                                entityID: savedEntity.id,
                                paragraphID: paragraphID,
                                surfaceForm: mention.surfaceForm,
                                charStart: charStart,
                                charEnd: charEnd,
                                confidence: mention.confidence
                            ))
                    }
                }

                let savedMentions = mentions
                try await db.write { database in
                    try savedEntity.insert(database)
                    for m in savedMentions { try m.insert(database) }
                }
            }

            print("✅ Chunk \(index): \(cleanedEntities.count) entities saved")

        } catch {
            print("⚠️ Chunk \(index) failed: \(error.localizedDescription)")
        }
    }

    private func reconcileEntities(bookID: UUID) async throws {
        // 1. Fetch all entities for this book from the DB
        let allEntities = try await dbQueue.read { db in 
            try NarrativeEntity.filter(Column("bookID") == bookID).fetchAll(db)
        }

        print("🔄 Reconciling \(allEntities.count) raw entities...")

        // 2. Group duplicates
        let groups = EntityReconciler.group(allEntities)
        print("    → Collapsed into \(groups.count) unique entities ")

        // 3. For each group, merge and update the DB
        for group in groups {
            let (winner, losers) = EntityReconciler.mergeGroup(group)

            try await dbQueue.write { db in 
                // Update the winner with merged aliases + new importanceScore
                try winner.update(db)

                // Re-point all mentions from the loser entities → winner entity
                for loserID in losers {
                    try db.execute(sql: "UPDATE entityMentions SET entityID = ? WHERE entityID = ?", arguments: [winner.id.uuidString, loserID.uuidString])
                }

                // Delete the duplicate entities
                for loserID in losers {
                    try db.execute(
                        sql: "DELETE FROM entities WHERE id = ?",
                        arguments: [loserID.uuidString]
                    )
                }
            }
        }

        print("✅ Entity Reconciliation Complete.")
    }

    private func extractAndSaveParagraphs(from publication: Publication, bookID: UUID) async throws
    {
        var absoluteIndex = 0

        // Ensure we handle Readium's resource fetching async
        for (chapterIndex, link) in publication.readingOrder.enumerated() {
            guard let resource = publication.get(link) else { continue }
            let result = await resource.readAsString()

            guard case .success(let html) = result else {
                print("⚠️ Failed to read resource: \(link.href)")
                continue
            }

            let chapterID = UUID()

            // Parse HTML to Paragraphs
            let extraction = try ParagraphIndexer.extractParagraphs(
                from: html,
                bookID: bookID,
                chapterID: chapterID,
                startingAbsoluteIndex: absoluteIndex
            )

            // Avoid saving empty chapters
            if extraction.paragraphs.isEmpty { continue }

            let chapter = NarrativeChapter(
                id: chapterID,
                bookID: bookID,
                indexInBook: chapterIndex,
                title: link.title,
                startParagraphID: nil,
                endParagraphID: nil
            )

            absoluteIndex = extraction.nextIndex

            // Save Chapter and Paragraphs to DB
            try await dbQueue.write { db in
                try chapter.insert(db)
                for p in extraction.paragraphs {
                    try p.insert(db)
                }
            }
            print(
                "   Saved Chapter \(chapterIndex): \(link.title ?? "Unnamed") with \(extraction.paragraphs.count) paragraphs."
            )
        }
    }

    private func buildAndLogChunks(bookID: UUID) async throws -> [ParagraphChunk] {
        let paragraphs = try await dbQueue.read {db in 
            return try NarrativeParagraph
                .filter(Column("bookID") == bookID)
                .order(Column("absoluteIndex"))
                .fetchAll(db)
        }

        let chunks = ChunkBuilder.buildChunks(from: paragraphs)

        for (i, chunk) in chunks.enumerated() {
            let firstIdx = chunk.paragraphs.first?.absoluteIndex ?? -1
            let lastIdx = chunk.paragraphs.last?.absoluteIndex ?? -1
            let charCount = chunk.paragraphs.reduce(0) { $0 + $1.text.count }
            let estTokens = charCount / ChunkBuilder.charsPerToken
            print(
                "  Chunk \(i): paras \(firstIdx)-\(lastIdx) (\(chunk.paragraphs.count) paras, ~\(estTokens) tokens, prefix: \(chunk.prefixParagraphs.count))")
        }

        return chunks
    }

    private func linkChapterBoundaries(bookID: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE chapters
                    SET
                        startParagraphID = (SELECT MIN(id) FROM paragraphs WHERE chapterID = chapters.id),
                        endParagraphID   = (SELECT MAX(id) FROM paragraphs WHERE chapterID = chapters.id)
                    WHERE bookID = ?
                    """, arguments: [bookID.uuidString])
        }
        print("✅ Chapter boundaries linked.")
    }


    private func saveBookStatus(_ book: Book) async throws {
        try await dbQueue.write { db in
            try book.update(db)
        }
    }

    enum PreprocessingError: Error {
        case invalidURL
        case publicationOpenFailed
    }
}
