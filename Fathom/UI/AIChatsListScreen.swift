import SwiftUI

struct AIChatsListScreen: View {
    let bookID: UUID
    var backendBookID: UUID? = nil
    let bookTitle: String

    @State private var threads: [AIThread] = []
    @State private var selectedThread: AIThread?
    @Environment(\.appTheme) var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .onAppear { reload() }
        .fullScreenCover(item: $selectedThread) { thread in
            if let backendID = backendBookID {
                AICompanionScreen(
                    bookID: bookID,
                    backendBookID: backendID,
                    selectedText: thread.passageText,
                    locatorJSON: thread.locatorJSON,
                    bookTitle: bookTitle,
                    threadID: thread.id,
                    onDismiss: {
                        selectedThread = nil
                        reload()
                    }
                )
                .environment(\.appTheme, theme)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AI Chats")
                .font(.title)
                .fontWeight(.bold)
            Spacer()
            Button("Done") { dismiss() }
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var threadList: some View {
        List {
            ForEach(threads) { thread in
                ThreadRow(thread: thread)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedThread = thread }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            AIThreadStore.shared.deleteThread(id: thread.id)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("No chats yet")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Select text while reading and tap\n\"Ask AI\" to start a conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func reload() {
        threads = AIThreadStore.shared.threads(forBookID: bookID)
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Thread Row

private struct ThreadRow: View {
    let thread: AIThread

    private var lastMessage: AIMessage? { thread.messages.last }
    private var messageCount: Int { thread.messages.count }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Passage quote
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)

                Text(thread.passageText)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            // Last message preview
            if let lastMessage {
                Text(lastMessage.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Footer
            HStack {
                Label(
                    "\(messageCount) message\(messageCount == 1 ? "" : "s")",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)

                Spacer()

                Text(Self.dateFormatter.string(from: thread.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
