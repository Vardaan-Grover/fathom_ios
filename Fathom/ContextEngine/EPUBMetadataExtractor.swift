import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

struct EPUBMetadata {
    let title: String
    let author: String?
    let language: String?
    let description: String?
    let publisher: String?
    let coverImageData: Data?
}

enum EPUBMetadataExtractor {
    @MainActor
    static func extract(from localURL: URL) async throws -> EPUBMetadata {
        let publication = try await openPublication(at: localURL)

        // title is String? in Readium — fall back to the filename if absent
        let title = publication.metadata.title
            ?? localURL.deletingPathExtension().lastPathComponent
        let author = publication.metadata.authors.first?.name
        let language = publication.metadata.languages.first
        let description = publication.metadata.description
        let publisher = publication.metadata.publishers.first?.name

        // cover() is an async function returning ReadResult<UIImage?>
        var coverData: Data? = nil
        if case .success(let image) = await publication.cover() {
            coverData = image?.pngData()
        }

        return EPUBMetadata(
            title: title,
            author: author,
            language: language,
            description: description,
            publisher: publisher,
            coverImageData: coverData
        )
    }

    @MainActor
    private static func openPublication(at localURL: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: localURL) else {
            throw EPUBMetadataError.invalidURL
        }
        let stack = ReadiumStack.shared
        let retrieveResult = await stack.assetRetriever.retrieve(url: fileURL)
        guard case .success(let asset) = retrieveResult else {
            throw EPUBMetadataError.openFailed
        }
        let openResult = await stack.publicationOpener.open(
            asset: asset, allowUserInteraction: false, sender: nil)
        guard case .success(let publication) = openResult else {
            throw EPUBMetadataError.openFailed
        }
        return publication
    }
}

enum EPUBMetadataError: Error {
    case invalidURL
    case openFailed
}
