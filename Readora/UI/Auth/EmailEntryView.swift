import SwiftUI

struct EmailEntryView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.appTheme) var theme

    var onSent: (String) -> Void

    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String? = nil
    @FocusState private var fieldFocused: Bool

    private let accent = Color(hex: "4A7DB5")

    private var emailIsValid: Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    private var canSend: Bool { emailIsValid && !isSending }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)

                    header
                        .padding(.bottom, 52)

                    form
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 40)

                    footer
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 40)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(accent)
                .padding(.bottom, 4)

            Text("Fathom")
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundStyle(theme.colors.primary)

            Text("Sign in with your email")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var form: some View {
        VStack(spacing: 14) {
            // Email field
            TextField("your@email.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(
                            fieldFocused ? accent.opacity(0.5) : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: fieldFocused)

            // Inline error
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(theme.typography.caption)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Primary button
            Button(action: { Task { await sendLink() } }) {
                ZStack {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send Magic Link")
                            .font(theme.typography.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSend ? accent : accent.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
    }

    private var footer: some View {
        Text("No password needed. We'll send you a secure one-tap link.")
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.secondary.opacity(0.6))
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func sendLink() async {
        guard canSend else { return }
        fieldFocused = false
        isSending = true
        errorMessage = nil

        do {
            try await authService.sendMagicLink(email: email.trimmingCharacters(in: .whitespaces))
            onSent(email.trimmingCharacters(in: .whitespaces))
        } catch {
            withAnimation {
                errorMessage = errorDescription(for: error)
            }
        }
        isSending = false
    }

    private func errorDescription(for error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("rate") || msg.contains("limit") {
            return "Too many requests. Please wait before trying again."
        }
        if msg.contains("network") || msg.contains("offline") || msg.contains("internet") {
            return "Check your connection and try again."
        }
        if msg.contains("invalid") && msg.contains("email") {
            return "Please enter a valid email address."
        }
        return "Something went wrong. Please try again."
    }
}
