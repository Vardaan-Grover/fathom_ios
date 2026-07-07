import Combine
import ReadiumShared  // Locator type used via ReadingStateStore
import SwiftUI

@MainActor
final class BookDetailsViewModel: ObservableObject {

    @Published var book: Book? = nil
    @Published var totalProgression: Double? = nil
    @Published var otherBooksByAuthor: [HomeBook] = []
    @Published var isLoading = true
    @Published var isEnablingAI = false
    @Published var enableAIError: String? = nil

    private let bookID: UUID
    let bookRepository: BookRepository

    init(bookID: UUID, bookRepository: BookRepository) {
        self.bookID = bookID
        self.bookRepository = bookRepository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let books = await bookRepository.listBooks()
        book = books.first { $0.id == bookID }

        if let loc = ReadingStateStore.shared.loadLocator(forBookID: bookID) {
            totalProgression = loc.locations.totalProgression
        }

        if let author = book?.author, !author.isEmpty {
            otherBooksByAuthor =
                books
                .filter { $0.id != bookID && $0.author == author }
                .map { HomeViewModel.makeHomeBook($0) }
        }
    }

    var pageCountText: String {
        guard let n = book?.estimatedPageCount else { return "—" }
        return "\(n)"
    }

    var readingTimeText: String {
        guard let mins = book?.estimatedReadingTimeMinutes else { return "—" }
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var progressText: String {
        guard let p = totalProgression else { return "—" }
        return "\(Int(p * 100))%"
    }

    func enableAI() async {
        guard var current = book else { return }
        guard let contentHash = current.contentHash else {
            enableAIError = "Book content hash missing. Please re-import the book."
            return
        }
        // For AI enablement we need the file fully on-device (to upload to R2).
        guard ICloudDownloadMonitor.shared.isReadable(bookFilename: current.localFilename) else {
            enableAIError = "Book file is not downloaded yet. Please wait for iCloud to finish syncing."
            return
        }
        guard let localURL = current.localURL else {
            enableAIError = "Local file not found."
            return
        }

        isEnablingAI = true
        enableAIError = nil

        do {
            let backendService = BackendService.shared

            // Flow C: same upload/register flow as Flow B, from book settings.
            let uploadInfo = try await backendService.getUploadURL(filename: localURL.lastPathComponent)
            let response = try await backendService.initBook(
                s3Key: uploadInfo.s3Key,
                title: current.title,
                author: current.author,
                language: current.language,
                contentHash: contentHash
            )

            current.aiEnabled = true
            current.backendBookID = response.bookID

            if response.duplicate {
                switch response.status {
                case "ready":
                    current.preprocessingStatus = .completed
                case "failed":
                    try await backendService.startIngestion(bookID: response.bookID)
                    current.preprocessingStatus = .inProgress
                default:
                    current.preprocessingStatus = .inProgress
                }
            } else {
                try await backendService.uploadEPUB(uploadURL: uploadInfo.uploadURL, fileURL: localURL)
                try await backendService.startIngestion(bookID: response.bookID)
                current.preprocessingStatus = .inProgress
            }

            await bookRepository.updateBook(current)
            book = current

            if current.preprocessingStatus == .inProgress {
                while true {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    let pollResponse = try await backendService.pollProcessingStatus(bookID: response.bookID)
                    switch pollResponse.status {
                    case "ready":
                        current.preprocessingStatus = .completed
                        await bookRepository.updateBook(current)
                        book = current
                        isEnablingAI = false
                        return
                    case "failed":
                        current.preprocessingStatus = .failed
                        await bookRepository.updateBook(current)
                        book = current
                        isEnablingAI = false
                        return
                    default:
                        break
                    }
                }
            }
        } catch {
            AppLogger.logError(tag: "BookDetailsViewModel", error)
            enableAIError = "Failed to enable AI. Please try again."
        }
        isEnablingAI = false
    }
}
