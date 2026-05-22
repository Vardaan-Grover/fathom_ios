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

    struct BookRow: Identifiable {
        let id: UUID
        let title: String
        let author: String?
        let book: Book
        let bytes: Int64
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
                            Text(byteFormatter.string(fromByteCount: row.bytes))
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    SectionHeader("By Book")
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

        // Run on a background task so we don't block the main thread on FS I/O.
        let result = await Task.detached(priority: .userInitiated) { () -> (Int64, Int64, [BookRow]) in
            let books = (try? DatabaseManager.shared.dbQueue.read { db in
                try Book.fetchAll(db)
            }) ?? []

            var rows: [BookRow] = []
            var bookBytesTotal: Int64 = 0
            for book in books {
                var bytes: Int64 = 0
                if let url = book.localURL {
                    bytes = Self.fileSize(url)
                }
                bookBytesTotal &+= bytes
                rows.append(BookRow(
                    id: book.id,
                    title: book.title,
                    author: book.author,
                    book: book,
                    bytes: bytes
                ))
            }
            rows.sort { $0.bytes > $1.bytes }

            let coverBytes = Self.directorySize(ICloudFileStore.shared.coversDirectory)
            return (bookBytesTotal + coverBytes, coverBytes, rows)
        }.value

        self.totalBytes = result.0
        self.coverBytes = result.1
        self.rows = result.2
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = attrs.fileSize {
                total &+= Int64(size)
            }
        }
        return total
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }
}
