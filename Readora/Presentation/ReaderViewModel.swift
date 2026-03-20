import Foundation
import Combine

@MainActor
final class ReaderViewModel: ObservableObject, Identifiable {
    
    let id = UUID()
    
    @Published var passage: Passage
    @Published var explanation: Explanation?
    @Published var isExplaining = false
    @Published var errorMessage: String?
    
    private let contextEngine: ContextEngine
    private let aiClient: AIClient
    
    init(
        passage: Passage,
        contextEngine: ContextEngine,
        aiClient: AIClient
    ) {
        self.passage = passage
        self.contextEngine = contextEngine
        self.aiClient = aiClient
    }
    
    func explainSelected() async {
        
        isExplaining = true
        errorMessage = nil
        
        defer { isExplaining = false }
        
        let bundle = contextEngine.makeBundle(from: passage)
        
        do {
            explanation = try await aiClient.explainPassage(context: bundle)
        } catch {
            errorMessage = "Could not fetch explanation."
        }
    }
}
