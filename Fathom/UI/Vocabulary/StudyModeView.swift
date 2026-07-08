import SwiftUI
import UIKit

// MARK: - Study Mode View

struct StudyModeView: View {
    @ObservedObject var viewModel: VocabularyTabViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme

    @State private var localSession: StudySession? = nil
    @State private var selectedAnswer: String? = nil
    @State private var isRevealed = false
    @State private var questionAppeared = false
    @State private var showResults = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            if showResults {
                StudyResultsView(
                    session: localSession,
                    onStudyAgain: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showResults = false
                            viewModel.startStudyMode()
                            localSession = viewModel.studySession
                            resetQuestion()
                        }
                    },
                    onDone: {
                        viewModel.dismissStudyMode()
                        dismiss()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            } else if let session = localSession {
                VStack(spacing: 0) {
                    StudyProgressHeader(
                        session: session,
                        onClose: {
                            viewModel.dismissStudyMode()
                            dismiss()
                        }
                    )
                    .padding(.horizontal, theme.layout.horizontalPadding)
                    .padding(.top, 16)

                    Spacer()

                    if let question = session.currentQuestion {
                        StudyPromptView(question: question, appeared: questionAppeared)
                            .padding(.horizontal, theme.layout.horizontalPadding)
                            .padding(.bottom, 32)

                        StudyChoicesGrid(
                            question: question,
                            selectedAnswer: $selectedAnswer,
                            isRevealed: $isRevealed,
                            onAnswerSelected: { answer in
                                selectedAnswer = answer
                                isRevealed = true
                                fireAnswerHaptic(correct: answer == question.correctAnswer)
                            }
                        )
                        .padding(.horizontal, theme.layout.horizontalPadding)
                    }

                    Spacer()

                    if isRevealed {
                        Button {
                            advanceQuestion()
                        } label: {
                            let isLast = (localSession?.currentIndex ?? 0) >= (localSession?.questions.count ?? 1) - 1
                            Text(isLast ? "See Results" : "Next")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(SpringPressStyle())
                        .padding(.horizontal, theme.layout.horizontalPadding)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Color.clear.frame(height: 56 + 40)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRevealed)
            }
        }
        .onAppear {
            localSession = viewModel.studySession
            triggerQuestionAppear()
        }
        .onChange(of: viewModel.studySession) { _, newSession in
            if let s = newSession { localSession = s }
        }
    }

    // MARK: - Question advance

    private func advanceQuestion() {
        guard var session = localSession else { return }

        // Score this answer
        if let answer = selectedAnswer, answer == session.currentQuestion?.correctAnswer {
            session.score += 1
        }
        session.currentIndex += 1
        localSession = session

        if session.isComplete {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                showResults = true
            }
            return
        }

        questionAppeared = false
        selectedAnswer = nil
        isRevealed = false
        triggerQuestionAppear()
    }

    private func triggerQuestionAppear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                questionAppeared = true
            }
        }
    }

    private func resetQuestion() {
        questionAppeared = false
        selectedAnswer = nil
        isRevealed = false
        showResults = false
        triggerQuestionAppear()
    }

    private func fireAnswerHaptic(correct: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(correct ? .success : .error)
    }
}

// MARK: - Progress Header

private struct StudyProgressHeader: View {
    let session: StudySession
    let onClose: () -> Void
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.colors.surface))
                }
                Spacer()
                Text("\(session.score) / \(session.currentIndex)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: session.score)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.colors.surface)
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: max(6, geo.size.width * CGFloat(session.currentIndex) / CGFloat(max(1, session.questions.count))),
                            height: 6
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: session.currentIndex)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Prompt View

private struct StudyPromptView: View {
    let question: StudyQuestion
    let appeared: Bool
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: 12) {
            switch question.promptStyle {
            case .fillInBlank:
                fillInBlankPrompt
            case .definitionToWord:
                definitionPrompt
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
    }

    private var fillInBlankPrompt: some View {
        VStack(spacing: 8) {
            Text("Fill in the blank")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondary)

            buildBlankText(from: question.promptText)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(theme.colors.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 8)
        }
    }

    private var definitionPrompt: some View {
        VStack(spacing: 8) {
            Text("Which word means…")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondary)

            Text(question.promptText)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(theme.colors.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 8)
        }
    }

    private func buildBlankText(from text: String) -> Text {
        let parts = text.components(separatedBy: "________")
        guard parts.count >= 2 else { return Text(text) }
        // SwiftUI.Text supports `+` but not `+=`, so the shorthand rule's
        // suggestion would not compile here.
        var result = Text(parts[0])
        // swiftlint:disable:next shorthand_operator
        result = result + Text("________")
            .foregroundColor(Color.accentColor)
            .underline()
            .bold()
        for i in 1..<parts.count {
            // swiftlint:disable:next shorthand_operator
            result = result + Text(parts[i])
        }
        return result
    }
}

// MARK: - Choices Grid

private struct StudyChoicesGrid: View {
    let question: StudyQuestion
    @Binding var selectedAnswer: String?
    @Binding var isRevealed: Bool
    let onAnswerSelected: (String) -> Void
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: 10) {
            ForEach(question.choices, id: \.self) { choice in
                StudyChoiceButton(
                    text: choice,
                    state: buttonState(for: choice),
                    isDisabled: isRevealed
                ) {
                    guard !isRevealed else { return }
                    onAnswerSelected(choice)
                }
            }
        }
    }

    private func buttonState(for choice: String) -> ChoiceButtonState {
        guard isRevealed else { return .idle }
        let isCorrect = choice == question.correctAnswer
        let isSelected = choice == selectedAnswer
        if isSelected && isCorrect { return .correctSelected }
        if isSelected && !isCorrect { return .wrongSelected }
        if !isSelected && isCorrect { return .correctUnselected }
        return .idle
    }
}

private enum ChoiceButtonState {
    case idle, correctSelected, wrongSelected, correctUnselected
}

private struct StudyChoiceButton: View {
    let text: String
    let state: ChoiceButtonState
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.appTheme) var theme

    private var bgColor: Color {
        switch state {
        case .idle: return theme.colors.surface
        case .correctSelected: return Color.green.opacity(0.15)
        case .wrongSelected: return Color.red.opacity(0.15)
        case .correctUnselected: return Color.clear
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return Color(.separator)
        case .correctSelected: return Color.green
        case .wrongSelected: return Color.red
        case .correctUnselected: return Color.green
        }
    }

    private var leadingIcon: String? {
        switch state {
        case .correctSelected: return "checkmark"
        case .wrongSelected: return "xmark"
        default: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state == .correctSelected ? Color.green : Color.red)
                }
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.colors.primary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(SpringPressStyle())
        .allowsHitTesting(!isDisabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: state)
    }
}

// MARK: - Results View

private struct StudyResultsView: View {
    let session: StudySession?
    let onStudyAgain: () -> Void
    let onDone: () -> Void
    @Environment(\.appTheme) var theme

    private var score: Int { session?.score ?? 0 }
    private var total: Int { max(1, session?.questions.count ?? 1) }
    private var percentage: Int { Int((Double(score) / Double(total)) * 100) }

    private var message: String {
        if percentage == 100 { return "Perfect!" }
        if percentage >= 70 { return "Well done!" }
        return "Keep studying"
    }

    private var accentForScore: Color {
        if percentage == 100 { return Color.green }
        if percentage >= 70 { return Color.accentColor }
        return Color.orange
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text("\(score)")
                    .font(.system(size: 80, weight: .bold, design: .serif))
                    .foregroundStyle(accentForScore)
                    + Text(" / \(total)")
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .foregroundStyle(theme.colors.secondary)

                Text(message)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.colors.primary)

                Text("\(percentage)% correct")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onStudyAgain) {
                    Text("Study Again")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(SpringPressStyle())

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(SpringPressStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
