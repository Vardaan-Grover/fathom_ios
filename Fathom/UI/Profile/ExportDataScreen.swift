import GRDB
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ExportDataScreen

struct ExportDataScreen: View {
    @State private var preparing = false
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var stats: ExportStats?

    var body: some View {
        Form {
            Section {
                heroRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if let stats {
                Section {
                    StatRow(symbol: "books.vertical.fill", color: Color(.systemBlue),
                            label: "Books", value: "\(stats.books)")
                    StatRow(symbol: "highlighter", color: .yellow,
                            label: "Highlights", value: "\(stats.highlights)")
                    StatRow(symbol: "note.text", color: Color(.systemIndigo),
                            label: "Notes", value: "\(stats.notes)")
                    StatRow(symbol: "bookmark.fill",
                            color: Color(red: 0.78, green: 0.08, blue: 0.15),
                            label: "Bookmarks", value: "\(stats.bookmarks)")
                    StatRow(symbol: "character.book.closed.fill", color: Color(.systemTeal),
                            label: "Saved Words", value: "\(stats.vocab)")
                } header: {
                    SectionHeader("Included")
                }
            }

            Section {
                Button {
                    Task { await prepareAndShare() }
                } label: {
                    HStack {
                        Spacer()
                        if preparing {
                            ProgressView().tint(.white)
                        } else {
                            Label("Export & Share", systemImage: "square.and.arrow.up.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .disabled(preparing)
                .listRowBackground(Color.accentColor)
                .foregroundStyle(Color.white)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Creates a JSON file you can save to Files, email to yourself, or share with another app.")
                }
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .sheet(item: Binding(
            get: { exportURL.map(IdentifiableURL.init) },
            set: { exportURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .task { await loadStats() }
    }

    // MARK: - Hero

    private var heroRow: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGreen).opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "square.and.arrow.up.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(.systemGreen))
                    .font(.system(size: 34))
            }
            Text("Your data, your file")
                .font(.system(size: 17, weight: .semibold))
            Text("All your books, notes, highlights, and vocabulary in a single JSON archive.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Stats

    struct ExportStats {
        let books: Int
        let highlights: Int
        let notes: Int
        let bookmarks: Int
        let vocab: Int
    }

    private func loadStats() async {
        let result = await Task.detached(priority: .userInitiated) { () -> ExportStats in
            let books = (try? DatabaseManager.shared.dbQueue.read { db in
                try Book.fetchCount(db)
            }) ?? 0
            let vocab = (try? DatabaseManager.shared.dbQueue.read { db in
                try SavedWord.filter(Column("deletedAt") == nil).fetchCount(db)
            }) ?? 0
            return ExportStats(
                books: books,
                highlights: HighlightStore.shared.allHighlights().count,
                notes: NoteStore.shared.allNotes().count,
                bookmarks: BookmarkStore.shared.allBookmarks().count,
                vocab: vocab
            )
        }.value
        stats = result
    }

    // MARK: - Prepare

    private func prepareAndShare() async {
        preparing = true
        error = nil
        defer { preparing = false }
        do {
            let url = try await DataExporter.export()
            exportURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - StatRow

private struct StatRow: View {
    let symbol: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            Text(label)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - IdentifiableURL

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
