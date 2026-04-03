import SwiftUI

struct AIThreadView: View {
    let threadID: UUID
    let bookID: UUID

    @State private var thread: AIThread?
    @State private var inputText: String = ""
    @State private var isWaitingForAI = false

    @FocusState private var isInputFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            PassageCard(thread: thread)
                                .padding()

                            ForEach(thread.messages) { message in
                                MessageBubble(message: message)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .id(message.id)

                            }

                            if isWaitingForAI {
                                TypingIndicator()
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                    .onChange(of: thread.messages.count) { _, _ in
                        if let last = thread.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isInputFocused = false
                    }
                }
            }

            Divider()
            suggestedPrompts
            inputBar
        }
        .navigationTitle("AI Companion")
        .navigationBarTitleDisplayMode(.inline)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                isInputFocused = false
            }
        )
        .onAppear {
            loadThread()
        }
    }

    private let suggestions = [
        "Explain this passage.",
        "What does this symbolize?",
        "Why does the author say this?",
        "What's the historical context?",
        "How does this connect to the theme?",
    ]

    private var suggestedPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask a follow-up…", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWaitingForAI)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func loadThread() {
        thread = AIThreadStore.shared.thread(id: threadID)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var currentThread = thread else { return }
        inputText = ""

        let userMessage = AIMessage(id: UUID(), role: .user, content: text, createdAt: Date())

        AIThreadStore.shared.appendMessage(userMessage, toThreadID: threadID)
        currentThread.messages.append(userMessage)
        thread = currentThread
        isWaitingForAI = true

        Task {
            do {
                let allMessages = AIThreadStore.shared.thread(id: threadID)?.messages ?? []
                let passageText = thread?.passageText ?? ""
                let client = try OpenAIClient.fromEnvironment()
                let responseText = try await client.chat(
                    messages: allMessages, passageText: passageText)
                let aiMessage = AIMessage(
                    id: UUID(),
                    role: .assistant,
                    content: responseText,
                    createdAt: Date()
                )
                AIThreadStore.shared.appendMessage(aiMessage, toThreadID: threadID)
                thread = AIThreadStore.shared.thread(id: threadID)
            } catch {
                let errorMessage = AIMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "Sorry, I couldn't reach the AI. Please try again.",
                    createdAt: Date()
                )
                AIThreadStore.shared.appendMessage(errorMessage, toThreadID: threadID)
                thread = AIThreadStore.shared.thread(id: threadID)
            }
            isWaitingForAI = false
        }
    }
}

private struct PassageCard: View {
    let thread: AIThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{201C}\(thread.passageText)\u{201D}")
                .font(.system(.body, design: .serif))
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            if let chapter = thread.chapterTitle {
                Text(chapter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.tint.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        if message.role == .assistant {
            // Editorial style — full width, soft background
            VStack(alignment: .leading, spacing: 6) {
                Text(message.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        } else if message.role == .user {
            // Small bubble aligned right
            HStack {
                Spacer()
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct TypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { animate = true }
    }
}
