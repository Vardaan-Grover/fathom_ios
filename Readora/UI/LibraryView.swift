import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {

    @StateObject var viewModel: LibraryViewModel
    @State private var readerVM: ReaderViewModel?
    @State private var readerBookURL: URL?
    @State private var readerBookTitle: String = ""
    @State private var readerBookID: UUID = UUID()

    @State private var isImporting = false
    @State private var refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {

        NavigationStack {

            List {
                ForEach(viewModel.books) { book in

                    Button {
                        Task {
                            if let url = book.localURL {
                                readerBookURL = url
                                readerBookTitle = book.title
                                readerBookID = book.id
                            } else {
                                readerVM = await viewModel.openBook(book)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(book.title)
                                .font(.headline)

                            if let author = book.author {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(statusLabel(for: book.preprocessingStatus))
                                    .font(.caption)
                                    .foregroundStyle(statusColor(for: book.preprocessingStatus))

                                if book.preprocessingStatus == .inProgress {
                                    ProgressView(value: Double(book.aiAnalysisProgress))
                                        .frame(maxWidth: 120)
                                    Text("\(Int(book.aiAnalysisProgress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                }
                .onDelete { indexSet in
                    for _ in indexSet {
                        continue
                    }
                }
            }
            .navigationTitle("Library")
            .task {
                await viewModel.load()
            }
            .onReceive(refreshTimer) { _ in
                Task {
                    await viewModel.load()
                }
            }
            .sheet(item: $readerVM) { vm in
                ReaderView(viewModel: vm)
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { readerBookURL != nil },
                    set: { if !$0 { readerBookURL = nil } }
                )
            ) {
                if let url = readerBookURL {
                    ReaderScreen(bookFileURL: url, bookTitle: readerBookTitle, bookID: readerBookID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "epub")!],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                Task {
                    await viewModel.importBook(from: url)
                }
            }
        }
    }

    private func statusLabel(for status: PreprocessingStatus) -> String {
        switch status {
        case .pending:
            return "Pending analysis"
        case .inProgress:
            return "Analyzing"
        case .completed:
            return "Analysis ready"
        case .failed:
            return "Analysis failed"
        }
    }

    private func statusColor(for status: PreprocessingStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
