import Foundation
import GRDB
import ReadiumShared
import ReadiumStreamer

actor BookPreprocessingCoordinator {
    private let dbQueue: DatabaseQueue
    private let backendService = BackendService.shared

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Opens a Readium publication. Runs briefly on the MainActor (required by ReadiumStack),
    /// then returns the Publication so heavy work can continue off the main thread.
    @MainActor
    private static func openPublication(at localURL: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: localURL) else {
            throw PreprocessingError.invalidURL
        }
        let stack = ReadiumStack.shared
        let retrieveResult = await stack.assetRetriever.retrieve(url: fileURL)
        guard case .success(let asset) = retrieveResult else {
            throw PreprocessingError.publicationOpenFailed
        }
        let openResult = await stack.publicationOpener.open(
            asset: asset, allowUserInteraction: false, sender: nil)
        guard case .success(let publication) = openResult else {
            throw PreprocessingError.publicationOpenFailed
        }
        return publication
    }

    func preprocess(book: Book) async {
        do {
            AppLogger.log(tag: "Preprocessing", "▶️ Started for book: \(book.title)")

            var processingBook = book
            processingBook.preprocessingStatus = .inProgress
            processingBook.aiAnalysisProgress = 0.01
            try await saveBookStatus(processingBook)

            guard let localURL = book.localURL else {
                throw PreprocessingError.invalidURL
            }

            let publication = try await BookPreprocessingCoordinator.openPublication(at: localURL)
            AppLogger.log(tag: "Preprocessing", "✅ EPUB opened: \(publication.metadata.title ?? "Unknown")")

            let totalWordCount = try await extractAndSaveParagraphs(from: publication, bookID: book.id)
            AppLogger.log(tag: "Preprocessing", "✅ Local paragraph extraction complete")

            processingBook.aiAnalysisProgress = 0.50
            try await saveBookStatus(processingBook)

            if FeatureFlags.aiCompanionEnabled, let backendID = book.backendBookID {
                AppLogger.log(tag: "Preprocessing", "⏳ Polling backend for AI ingestion status...")
                try await waitForBackendReady(bookID: backendID)
            } else {
                AppLogger.log(tag: "Preprocessing", "ℹ️ AI dormant/disabled — skipping backend polling")
            }

            processingBook.aiAnalysisProgress = 1.0
            processingBook.preprocessingStatus = .completed
            if totalWordCount > 0 {
                processingBook.estimatedPageCount = max(1, totalWordCount / 250)
                processingBook.estimatedReadingTimeMinutes = max(1, totalWordCount / 250)
            }
            try await saveBookStatus(processingBook)
            AppLogger.log(tag: "Preprocessing", "✅ Book ready: \(book.title)")

        } catch {
            AppLogger.logError(tag: "Preprocessing", error)
            var failedBook = book
            failedBook.preprocessingStatus = .failed
            try? await saveBookStatus(failedBook)
        }
    }

    // Polls the backend every 3 seconds until the book status is "ready" or "failed".
    private func waitForBackendReady(bookID: UUID) async throws {
        while true {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let response = try await backendService.pollProcessingStatus(bookID: bookID)
            switch response.status {
            case "ready":
                AppLogger.log(tag: "Preprocessing", "✅ Backend ingestion complete")
                return
            case "failed":
                throw PreprocessingError.backendIngestionFailed
            case "processing", "pending":
                break
            default:
                AppLogger.log(tag: "Preprocessing", "⚠️ Unknown backend status: \(response.status)")
            }
        }
    }

    @discardableResult
    private func extractAndSaveParagraphs(from publication: Publication, bookID: UUID) async throws -> Int {
        var absoluteIndex = 0
        var totalWordCount = 0

        for (chapterIndex, link) in publication.readingOrder.enumerated() {
            guard let resource = publication.get(link) else { continue }
            let result = await resource.readAsString()

            guard case .success(let html) = result else {
                AppLogger.log(tag: "Preprocessing", "⚠️ Failed to read resource: \(link.href)")
                continue
            }

            let chapterID = UUID()
            let hrefString = "\(link.href)"

            let extraction = try ParagraphIndexer.extractParagraphs(
                from: html,
                bookID: bookID,
                chapterID: chapterID,
                startingAbsoluteIndex: absoluteIndex
            )

            try await persistChapterAndParagraphs(
                bookID: bookID,
                chapterID: chapterID,
                href: hrefString,
                indexInBook: chapterIndex,
                title: link.title ?? "Chapter \(chapterIndex + 1)",
                paragraphs: extraction.paragraphs
            )

            totalWordCount += extraction.paragraphs.reduce(0) { $0 + $1.text.split(separator: " ").count }
            absoluteIndex = extraction.nextIndex
        }

        return totalWordCount
    }

    private func persistChapterAndParagraphs(
        bookID: UUID,
        chapterID: UUID,
        href: String?,
        indexInBook: Int,
        title: String?,
        paragraphs: [NarrativeParagraph]
    ) async throws {
        try await dbQueue.write { db in
            // Insert chapter first so paragraphs.chapterID FK resolves.
            // startParagraphID/endParagraphID have no FK constraint, so nil is safe here.
            var chapter = NarrativeChapter(
                id: chapterID,
                bookID: bookID,
                indexInBook: indexInBook,
                href: href,
                title: title,
                startParagraphID: nil,
                endParagraphID: nil
            )
            try chapter.insert(db)

            // Insert paragraphs and track the first/last autoincrement rowids.
            var firstParagraphID: Int64?
            var lastParagraphID: Int64?
            for p in paragraphs {
                try p.insert(db)
                let rowID = db.lastInsertedRowID
                if firstParagraphID == nil { firstParagraphID = rowID }
                lastParagraphID = rowID
            }

            // Back-fill the chapter's paragraph range.
            chapter.startParagraphID = firstParagraphID
            chapter.endParagraphID = lastParagraphID
            try chapter.update(db)
        }
    }

    private func saveBookStatus(_ book: Book) async throws {
        try await dbQueue.write { db in
            try book.update(db)
        }
    }

    enum PreprocessingError: Error {
        case invalidURL
        case publicationOpenFailed
        case backendIngestionFailed
    }
}
