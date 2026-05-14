import ReadiumShared
import SwiftUI

struct TableOfContentsSheet: View {
    let bookID: UUID
    let bookTitle: String
    let publication: Publication
    let currentPage: Int
    let totalPages: Int
    let currentLocator: Locator?
    let settings: ReaderSettings
    let onSelect: (ReadiumShared.Link) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tableOfContents: [ReadiumShared.Link] = []

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .opacity(0.4)

            tocList
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "book.closed.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 60)
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                if totalPages > 0 {
                    Text("Page \(currentPage) of \(totalPages)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding()
        .padding(.top, 10)
    }

    @ViewBuilder
    private var tocList: some View {
        ScrollViewReader { proxy in
            let entries = flattenedTOCEntries(tableOfContents)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        tocButton(for: entry, at: index)

                        if index < entries.count - 1 {
                            Divider()
                                .opacity(0.4)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .task {
                if let links = try? await publication.tableOfContents().get() {
                    self.tableOfContents = links
                    if let idx = activeEntryIndex(in: flattenedTOCEntries(links)) {
                        try? await Task.sleep(for: .milliseconds(150))
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private func activeEntryIndex(in entries: [TOCEntry]) -> Int? {
        guard let locator = currentLocator else { return nil }
        let currentPath = "\(locator.href)".components(separatedBy: "#").first ?? "\(locator.href)"
        let currentFilename = currentPath.split(separator: "/").last.map(String.init) ?? ""

        for (idx, entry) in entries.enumerated().reversed() {
            let linkPath =
                "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
            let linkFilename = linkPath.split(separator: "/").last.map(String.init) ?? ""
            if linkPath == currentPath
                || (!currentFilename.isEmpty && !linkFilename.isEmpty
                    && linkFilename == currentFilename)
            {
                return idx
            }
        }
        return nil
    }

    @ViewBuilder
    private func tocButton(for entry: TOCEntry, at index: Int) -> some View {
        let isActive = currentLocator != nil && "\(currentLocator!.href)" == "\(entry.link.href)"
        Button {
            onSelect(entry.link)
            dismiss()
        } label: {
            HStack {
                Text(entry.link.title ?? "Chapter \(index + 1)")
                    .font(
                        .system(
                            size: entry.depth == 0 ? 16 : 14,
                            weight: isActive ? .semibold : (entry.depth == 0 ? .medium : .regular),
                            design: .default
                        )
                    )
                    .foregroundStyle(
                        .primary
                    )
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.leading, 16 + CGFloat(entry.depth) * 20)
            .padding(.trailing, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.primary.opacity(0.06) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}
