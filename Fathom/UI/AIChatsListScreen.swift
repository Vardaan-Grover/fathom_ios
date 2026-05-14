import SwiftUI

struct AIChatsListScreen: View {
    let bookID: UUID
    var backendBookID: UUID? = nil
    let bookTitle: String

    @State private var threads: [AIThread] = []
    @State private var selectedThread: AIThread?
    @Environment(\.appTheme) var theme
    @Environment(\.dismiss) private var dismiss

    private let aiGradient = LinearGradient(
        colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.4)
            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
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

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("AI Chats")
                        .font(.system(size: 22, weight: .bold))
                    if !threads.isEmpty {
                        Text("\(threads.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(aiGradient))
                            .contentTransition(.numericText())
                    }
                }
                Text(bookTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(threads) { thread in
                    ThreadCard(thread: thread, gradient: aiGradient) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        selectedThread = thread
                    }
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(aiGradient.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(aiGradient)
            }
            VStack(spacing: 8) {
                Text("No Chats Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 24)
                Text("Select text while reading and tap\n\"Ask AI\" to start a conversation.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - Helpers

    private func reload() {
        threads = AIThreadStore.shared.threads(forBookID: bookID)
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Thread Card

private struct ThreadCard: View {
    let thread: AIThread
    let gradient: LinearGradient
    let onTap: () -> Void

    private var lastUserMessage: AIMessage? {
        thread.messages.first(where: { $0.role == .user })
    }

    private var lastAssistantMessage: AIMessage? {
        thread.messages.last(where: { $0.role == .assistant })
    }

    private var messageCount: Int { thread.messages.count }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Passage quote
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(gradient)
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    Text(thread.passageText)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Text(Self.dateFormatter.string(from: thread.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                if let msg = lastAssistantMessage ?? lastUserMessage {
                    Divider()
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .opacity(0.45)

                    Text(msg.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }

                // Footer
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("\(messageCount) \(messageCount == 1 ? "message" : "messages")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let chapter = thread.chapterTitle, !chapter.isEmpty {
                        Text(chapter)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.opaqueSeparator).opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SpringPressStyle())
    }
}
