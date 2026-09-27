import GRDB
import SwiftUI

// MARK: - StorageUsageScreen
//
// Shows total + per-book storage used by the app's book and cover files.

struct StorageUsageScreen: View {
    @State private var totalBytes: Int64 = 0
    @State private var coverBytes: Int64 = 0
    @State private var rows: [BookRow] = []
    @State private var loading = true
    @State private var showNotInICloudAlert = false

    nonisolated struct BookRow: Identifiable, Sendable {
        let id: UUID
        let title: String
        let author: String?
        let book: Book
        let bytes: Int64
        /// Whether this device holds its own copy. False only for a book the
        /// reader removed with "Remove Download", or one still arriving.
        let isOnDevice: Bool
    }

    var body: some View {
        List {
            Section {
                summaryRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            MiniBookCover(book: row.book, width: 28, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                if let author = row.author, !author.isEmpty {
                                    Text(author)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if row.isOnDevice {
                                Text(byteFormatter.string(fromByteCount: row.bytes))
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("In iCloud", systemImage: "icloud")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            if let filename = row.book.localFilename {
                                if row.isOnDevice {
                                    Button("Remove Download", systemImage: "icloud.and.arrow.up") {
                                        removeDownload(filename)
                                    }
                                    .tint(.orange)
                                } else {
                                    Button("Download", systemImage: "icloud.and.arrow.down") {
                                        ICloudDownloadMonitor.shared.requestDownload(filename: filename)
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    SectionHeader("By Book")
                } footer: {
                    Text("Every book stays downloaded so it opens offline. Swipe to remove one from this device — it stays in iCloud and downloads again when you open it.")
                }

                Section {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(Color(.systemGray))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray).opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 7))
                        Text("Covers")
                        Spacer()
                        Text(byteFormatter.string(fromByteCount: coverBytes))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !loading {
                Section {
                    Text("No book files on this device yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .task { await load() }
        .refreshable { await load() }
        .alert("Not in iCloud yet", isPresented: $showNotInICloudAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This book hasn't finished uploading to iCloud, so this device holds the only copy. Try again once it has uploaded.")
        }
    }

    private func removeDownload(_ filename: String) {
        Task {
            let removed = await BookFileSync.shared.removeDownload(
                BookFileRef(kind: .book, filename: filename))
            if !removed { showNotInICloudAlert = true }
            await load()
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.systemBlue).opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "internaldrive.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(.systemBlue))
                    .font(.system(size: 34))
            }

            Text(byteFormatter.string(fromByteCount: totalBytes))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: totalBytes)

            Text("Total Used")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Loader

    private func load() async {
        loading = true
        defer { loading = false }

        let books = await Task.detached(priority: .userInitiated) {
            (try? DatabaseManager.shared.dbQueue.read { db in try Book.fetchAll(db) }) ?? []
        }.value

        // Sized off the main thread through a nonisolated helper: a static
        // func on this View would be main-actor isolated and pull the file
        // I/O straight back onto the main thread.
        let result = await CoverImageLoader.offMain { StorageScan.scan(books) }

        self.totalBytes = result.0
        self.coverBytes = result.1
        self.rows = result.2
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }
}

/// Measures what the library occupies on this device. `nonisolated` so the
/// scan really runs where it is sent.
nonisolated enum StorageScan {

    static func scan(_ books: [Book]) -> (Int64, Int64, [StorageUsageScreen.BookRow]) {
        let store = ICloudFileStore.shared
        var rows: [StorageUsageScreen.BookRow] = []
        var bookBytesTotal: Int64 = 0
        for book in books {
            var bytes: Int64 = 0
            var onDevice = false
            if let filename = book.localFilename {
                let ref = BookFileRef(kind: .book, filename: filename)
                if let url = store.localURL(ref), FileManager.default.fileExists(atPath: url.path) {
                    onDevice = true
                    bytes = fileSize(url)
                }
            }
            bookBytesTotal &+= bytes
            rows.append(StorageUsageScreen.BookRow(
                id: book.id, title: book.title, author: book.author,
                book: book, bytes: bytes, isOnDevice: onDevice))
        }
        rows.sort { $0.bytes > $1.bytes }

        let coverBytes = directorySize(store.localDirectory(.cover))
        return (bookBytesTotal + coverBytes, coverBytes, rows)
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func directorySize(_ url: URL?) -> Int64 {
        guard let url,
              let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total &+= Int64(size)
            }
        }
        return total
    }
}
