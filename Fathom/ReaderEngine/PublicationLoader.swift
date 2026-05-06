import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer

@MainActor
final class PublicationLoader: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(Publication)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let stack: ReadiumStack

    init() {
        self.stack = .shared
    }

    init(stack: ReadiumStack) {
        self.stack = stack
    }

    func load(fromLocalFileURL url: URL) async {
        if case .loading = state { return }
        if case .loaded = state { return }

        state = .loading
        AppLogger.log(tag: "PublicationLoader", "Attempting to load EPUB from URL: \(url)")

        // Readium uses its own AbsoluteURL types (FileURL / HTTPURL)
        guard let fileURL = FileURL(url: url) else {
            AppLogger.log(tag: "PublicationLoader", "Invalid file URL: \(url)")
            state = .failed("Invalid file URL")
            return
        }

        AppLogger.log(tag: "PublicationLoader", "Retrieving asset for: \(fileURL)")
        let retrieveResult = await stack.assetRetriever.retrieve(url: fileURL)

        switch retrieveResult {
        case .failure(let error):
            AppLogger.logError(tag: "PublicationLoader", error)
            state = .failed("Failed to retrieve asset: \(error)")
            return
        case .success(let asset):
            AppLogger.log(
                tag: "PublicationLoader",
                "Asset retrieved successfully. Format: \(String(describing: asset.format)). Opening publication..."
            )
            let openResult = await stack.publicationOpener.open(
                asset: asset,
                allowUserInteraction: false,
                sender: nil
            )

            switch openResult {
            case .failure(let error):
                AppLogger.logError(tag: "PublicationLoader", error)
                state = .failed("Failed to open publication: \(error)")
            case .success(let publication):
                AppLogger.log(
                    tag: "PublicationLoader",
                    "Publication opened successfully. Title: \(String(describing: publication.metadata.title))."
                )
                state = .loaded(publication)
            }
        }
    }
}
