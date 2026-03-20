import SwiftUI

struct AIThreadsListView: View {
    let bookID: UUID
    let bookTitle: String

    @State private var threads: [AIThread] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if threads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        Text("No conversations yet...")
                        .font(.headline)
                        Text("Select text while reading and tap \"Ask AI\" to start a conversation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(threads) { thread in 
                            NavigationLink {
                                AIThreadView(threadID: thread.id, bookID: bookID)
                            } label: {
                                ThreadRow(thread: thread)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                AIThreadStore.shared.deleteThread(id: threads[index].id)
                            }
                            threads.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("AI Threads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .onAppear { loadThreads() }
        }
    }

    private func loadThreads() {
        threads = AIThreadStore.shared.threads(forBookID: bookID)
            .sorted {$0.createdAt > $1.createdAt}
    }
}

private struct ThreadRow: View {
    let thread: AIThread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thread.passageText)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack {
                Text(messageCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(thread.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var messageCountLabel: String {
        let count = thread.messages.filter { $0.role != .system }.count
        return count == 1 ? "1 message" : "\(count) messages"
    }
}