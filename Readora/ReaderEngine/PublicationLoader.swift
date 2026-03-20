import Foundation
import Combine
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
        state = .loading
        
        // Readium uses its own AbsoluteURL types (FileURL / HTTPURL)
        guard let fileURL = FileURL(url: url) else {
            state = .failed("Invalid file URL")
            return
        }
        
        let retrieveResult = await stack.assetRetriever.retrieve(url: fileURL)
        
        switch retrieveResult {
        case .failure(let error):
                state = .failed("Failed to retrieve asset: \(error)")
                return
        case .success(let asset):
            let openResult = await stack.publicationOpener.open(
                asset: asset,
                allowUserInteraction: false,
                sender: nil
            )
            
            switch openResult {
            case .failure(let error):
                state = .failed("Failed to open publication: \(error)")
            case .success(let publication):
                state = .loaded(publication)
            }
        }
    }
}
