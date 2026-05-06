import Foundation
import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

@MainActor
final class ReadiumStack: @unchecked Sendable {
    static let shared = ReadiumStack()

    let httpClient: HTTPClient
    let assetRetriever: AssetRetriever
    let publicationOpener: PublicationOpener
    let httpServer: GCDHTTPServer

    private init() {
        // 1) Networking support (even for local books, this is fine)
        let httpClient = DefaultHTTPClient()
        self.httpClient = httpClient

        // 2) Retrieve assets from URLs (file://, http://, etc.)
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        self.assetRetriever = assetRetriever

        // 4) HTTP Server
        self.httpServer = GCDHTTPServer(assetRetriever: assetRetriever)

        // 3) Parse/open publications
        let parser = DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )

        self.publicationOpener = PublicationOpener(
            parser: parser,
            contentProtections: []
        )
    }
}
