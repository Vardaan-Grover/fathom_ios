import SwiftUI

struct ReaderView: View {
    
    @StateObject var viewModel: ReaderViewModel
    
    var body: some View {
        
        VStack {
            
            ScrollView {
                
                VStack(alignment: .leading, spacing: 20) {
                    
                    if let chapter = viewModel.passage.chapterTitle {
                        Text(chapter)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(viewModel.passage.beforeText)
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.passage.selectedText)
                        .font(.headline)
                        .textSelection(.enabled)
                    
                    Text(viewModel.passage.afterText)
                        .foregroundStyle(.secondary)
                    
                    if let explanation = viewModel.explanation {
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 10) {
                            
                            Text("AI Explanation")
                                .font(.headline)
                            
                            Text(explanation.output)
                                .textSelection(.enabled)
                            
                        }
                    }
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    }
                    
                }
                .padding()
                
            }
            
            Divider()
            
            Button {
                Task {
                    await viewModel.explainSelected()
                }
            } label: {
                
                if viewModel.isExplaining {
                    ProgressView()
                } else {
                    Text("Explain Passage")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
        }
    }
}
