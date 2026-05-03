import Combine
import SwiftUI

// MARK: - Models

struct AICompanionMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var isStreaming: Bool = false
}

// MARK: - ViewModel

@MainActor
final class AICompanionViewModel: ObservableObject {
    @Published var messages: [AICompanionMessage] = []
    @Published var inputText: String = ""
    @Published var isTyping = false

    private let bookID: UUID
    private let passageText: String
    private var threadID: UUID?
    private var conversationHistory: [ConversationMessage] = []

    init(bookID: UUID, passageText: String, threadID: UUID? = nil) {
        self.bookID = bookID
        self.passageText = passageText
        self.threadID = threadID

        if let threadID,
           let thread = AIThreadStore.shared.thread(id: threadID) {
            self.messages = thread.messages.map { msg in
                AICompanionMessage(isUser: msg.role == .user, text: msg.content)
            }
        }
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if threadID == nil {
            let newThread = AIThread(
                id: UUID(),
                bookID: bookID,
                passageText: passageText,
                locatorJSON: nil,
                chapterTitle: nil,
                createdAt: Date(),
                messages: []
            )
            AIThreadStore.shared.createThread(newThread)
            threadID = newThread.id
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            messages.append(AICompanionMessage(isUser: true, text: trimmed))
        }

        if let threadID {
            let userMsg = AIMessage(id: UUID(), role: .user, content: trimmed, createdAt: Date())
            AIThreadStore.shared.appendMessage(userMsg, toThreadID: threadID)
        }

        inputText = ""
        isTyping = true

        let historySnapshot = conversationHistory

        Task {
            let absoluteIndex =
                await NarrativeContextStore.shared.getAbsoluteIndex(
                    for: bookID, selectedText: passageText) ?? 0
            do {
                let answer = try await BackendService.shared.queryBook(
                    bookID: bookID, absoluteIndex: absoluteIndex, query: trimmed,
                    messages: historySnapshot)
                conversationHistory.append(ConversationMessage(role: "user", content: trimmed))
                conversationHistory.append(ConversationMessage(role: "assistant", content: answer))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    isTyping = false
                    messages.append(
                        AICompanionMessage(isUser: false, text: answer, isStreaming: true))
                }
                if let threadID {
                    let aiMsg = AIMessage(id: UUID(), role: .assistant, content: answer, createdAt: Date())
                    AIThreadStore.shared.appendMessage(aiMsg, toThreadID: threadID)
                }
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    isTyping = false
                    messages.append(
                        AICompanionMessage(
                            isUser: false, text: "Error: \(error.localizedDescription)",
                            isStreaming: true))
                }
            }
        }
    }
}

// MARK: - Screen

struct AICompanionScreen: View {
    let bookID: UUID
    let selectedText: String
    let bookTitle: String
    let onDismiss: () -> Void

    @StateObject private var viewModel: AICompanionViewModel
    @Environment(\.appTheme) var theme
    @FocusState private var isInputFocused: Bool

    init(
        bookID: UUID,
        selectedText: String,
        bookTitle: String,
        threadID: UUID? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.bookID = bookID
        self.selectedText = selectedText
        self.bookTitle = bookTitle
        self.onDismiss = onDismiss
        self._viewModel = StateObject(
            wrappedValue: AICompanionViewModel(
                bookID: bookID, passageText: selectedText, threadID: threadID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ContextCard(selectedText: selectedText, bookTitle: bookTitle)
                .padding(.horizontal, theme.layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ChatHistoryView(
                messages: viewModel.messages,
                isTyping: viewModel.isTyping,
                theme: theme,
                onTap: { isInputFocused = false }
            )
            .safeAreaInset(edge: .bottom) {
                GradientInputBar(
                    text: $viewModel.inputText,
                    isFocused: $isInputFocused,
                    onSend: { viewModel.sendMessage() }
                )
                .padding(.horizontal, theme.layout.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background {
                    LinearGradient(
                        colors: [
                            theme.colors.background.opacity(0.0),
                            theme.colors.background.opacity(0.8),
                            theme.colors.background,
                            theme.colors.background,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.primary)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("Ask Fathom")
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.primary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

// MARK: - Context Card

private struct ContextCard: View {
    let selectedText: String
    let bookTitle: String
    @Environment(\.appTheme) var theme

    @State private var isExpanded = false

    private let highlightGradient = LinearGradient(
        colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        }) {
            HStack(alignment: isExpanded ? .top : .center, spacing: 12) {
                // Icon
                Image(systemName: "quote.opening")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(highlightGradient)
                    .frame(width: 24, height: 24)
                    .background(highlightGradient.opacity(0.15), in: Circle())
                    .padding(.top, isExpanded ? 2 : 0)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedText)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(theme.colors.primary)
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)

                    if isExpanded {
                        HStack(spacing: 4) {
                            Image(systemName: "book.closed.fill")
                            Text(bookTitle)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.colors.secondary)
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)

                // Chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
                    .padding(.top, isExpanded ? 6 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.colors.separator.opacity(0.5), lineWidth: 0.5)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat History

private struct ChatHistoryView: View {
    let messages: [AICompanionMessage]
    let isTyping: Bool
    let theme: AppTheme
    let onTap: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if messages.isEmpty {
                    emptyState
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            ChatBubble(message: message, theme: theme)
                                .id(message.id)
                        }
                        if isTyping {
                            TypingIndicator(theme: theme)
                                .id("typing")
                                .transition(
                                    .scale(scale: 0.85, anchor: .bottomLeading).combined(
                                        with: .opacity))
                        }
                    }
                    .padding(.horizontal, theme.layout.horizontalPadding)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture(perform: onTap)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: isTyping) { _, typing in
                if typing {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Ask me anything about\nyour reading")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: AICompanionMessage
    let theme: AppTheme
    @State private var phase: Double = 0.0
    @State private var reportedHeight: CGFloat = 24.0

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 56) }
            bubbleContent
            if !message.isUser { Spacer(minLength: 56) }
        }
        .transition(
            .asymmetric(
                insertion: .scale(
                    scale: 0.85, anchor: message.isUser ? .bottomTrailing : .bottomLeading
                )
                .combined(with: .opacity),
                removal: .opacity
            )
        )
        .onAppear {
            if !message.isUser && message.isStreaming && phase == 0.0 {
                let duration = max(0.3, Double(message.text.count) * 0.008)
                withAnimation(.easeOut(duration: duration)) {
                    phase = 1.0
                }
            } else if phase == 0.0 {
                phase = 1.0
            }
        }
    }

    private var bubbleContent: some View {
        Group {
            if !message.isUser && message.isStreaming {
                if #available(iOS 18.0, *) {
                    Text(message.text)
                        .textRenderer(StreamingTextRenderer(progress: phase))
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primary)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onAppear {
                                    reportedHeight = proxy.size.height
                                }
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            height: phase == 1.0
                                ? nil : max(min(24, reportedHeight), reportedHeight * phase),
                            alignment: .top
                        )
                        .clipped()
                } else {
                    Text(message.text)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primary)
                }
            } else if !message.isUser {
                if #available(iOS 18.0, *) {
                    Text(message.text)
                        .textRenderer(StreamingTextRenderer(progress: 1.0))
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primary)
                } else {
                    Text(message.text)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primary)
                }
            } else {
                Text(message.text)
                    .font(theme.typography.body)
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isUser {
            LinearGradient(
                colors: [Color(hex: "E87AB8"), Color(hex: "8A92E8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.clear.background(.regularMaterial)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    let theme: AppTheme
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.colors.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animating ? -3 : 3)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}

// MARK: - Gradient Input Bar

private struct GradientInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSend: () -> Void

    @Environment(\.appTheme) var theme

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            inputField
            if hasText {
                sendButton
                    .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hasText)
    }

    private var inputField: some View {
        TextField("Message Fathom", text: $text, axis: .vertical)
            .lineLimit(1...5)
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.primary)
            .focused($isFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(theme.colors.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .borderBeam(
                border: .primary,
                // beam: [Color(hex: "FF6EB4"), Color(hex: "7C86F0"), Color(hex: "4052E3")],
                beam: [.green, .blue, .pink, .orange, .indigo],
                beamBlur: 8,
                cornerRadius: 22,
                isEnabled: isFocused
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isFocused)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0"), Color(hex: "4052E3")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        }
        .padding(.bottom, 5)
    }
}

// MARK: - Previews

#Preview("Empty State") {
    AICompanionScreen(
        bookID: UUID(),
        selectedText:
            "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief.",
        bookTitle: "A Tale of Two Cities",
        onDismiss: {}
    )
    .environment(\.appTheme, .default)
}
