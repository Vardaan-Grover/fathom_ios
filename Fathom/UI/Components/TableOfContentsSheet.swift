import SwiftUI
import ReadiumShared

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
                .background(settings.colorTheme.foregroundColor.opacity(0.2))

            tocList
        }
        .background(settings.colorTheme.backgroundColor)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if let links = try? await publication.tableOfContents().get() {
                self.tableOfContents = links
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "book.closed.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 60)
                .foregroundStyle(settings.colorTheme.foregroundColor.opacity(0.8))
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(3)
                    .foregroundStyle(settings.colorTheme.foregroundColor)

                if totalPages > 0 {
                    Text("Page \(currentPage) of \(totalPages)")
                        .font(.subheadline)
                        .foregroundStyle(settings.colorTheme.foregroundColor.opacity(0.6))
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(settings.colorTheme.backgroundColor)
                    .padding(10)
                    .background(settings.colorTheme.foregroundColor)
                    .clipShape(Circle())
            }
        }
        .padding()
        .padding(.top, 10)
    }

    @ViewBuilder
    private var tocList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tableOfContents.enumerated()), id: \.offset) { index, link in
                    tocButton(for: link, at: index)

                    if index < tableOfContents.count - 1 {
                        Divider()
                            .background(settings.colorTheme.foregroundColor.opacity(0.1))
                            .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func tocButton(for link: ReadiumShared.Link, at index: Int) -> some View {
        Button {
            onSelect(link)
            dismiss()
        } label: {
            HStack {
                Text(link.title ?? "Chapter \(index + 1)")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundStyle(settings.colorTheme.foregroundColor)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        (currentLocator != nil && "\(currentLocator!.href)" == "\(link.href)") ?
                        settings.colorTheme.foregroundColor.opacity(0.15) :
                        Color.clear
                    )
            )
            .padding(.horizontal, 8)
        }
    }
}
