import SwiftUI

struct MagicLinkSentView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.appTheme) var theme

    let email: String
    var onBack: () -> Void

    @State private var cooldown = 30
    @State private var isResending = false
    @State private var resendError: String? = nil
    @State private var resendSuccess = false

    private let accent = Color(hex: "4A7DB5")

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    icon
                    textContent
                    iphoneCallout
                }
                .padding(.horizontal, 28)

                Spacer()

                bottomActions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .onAppear { startCooldown() }
    }

    // MARK: - Sections

    private var icon: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.1))
                .frame(width: 100, height: 100)
            Circle()
                .strokeBorder(accent.opacity(0.15), lineWidth: 1)
                .frame(width: 100, height: 100)
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(accent)
        }
    }

    private var textContent: some View {
        VStack(spacing: 10) {
            Text("Check your email")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(theme.colors.primary)
                .multilineTextAlignment(.center)

            Group {
                Text("We sent a magic link to\n") +
                Text(email)
                    .bold()
                    .foregroundStyle(theme.colors.primary)
            }
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var iphoneCallout: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "iphone.gen3")
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.top, 1)

            Text("Open it on **this iPhone** — the link only works on iOS. Links opened on Mac or iPad won't sign you in.")
                .font(.callout)
                .foregroundStyle(theme.colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            // Resend status feedback
            if let resendError {
                Text(resendError)
                    .font(theme.typography.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
            if resendSuccess {
                Label("Link sent!", systemImage: "checkmark.circle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            // Resend button
            Button(action: { Task { await resend() } }) {
                ZStack {
                    if isResending {
                        ProgressView().tint(accent)
                    } else if cooldown > 0 {
                        Text("Resend in \(cooldown)s")
                            .foregroundStyle(theme.colors.secondary)
                    } else {
                        Text("Resend link")
                            .foregroundStyle(accent)
                    }
                }
                .font(theme.typography.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .disabled(cooldown > 0 || isResending)
            .animation(.easeInOut(duration: 0.15), value: cooldown)

            // Back
            Button("Use a different email", action: onBack)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: - Actions

    private func resend() async {
        isResending = true
        resendError = nil
        resendSuccess = false

        do {
            try await authService.sendMagicLink(email: email)
            withAnimation { resendSuccess = true }
            startCooldown()
            // Hide success after 3s
            try? await Task.sleep(for: .seconds(3))
            withAnimation { resendSuccess = false }
        } catch {
            withAnimation { resendError = "Couldn't resend. Please try again." }
        }
        isResending = false
    }

    private func startCooldown() {
        cooldown = 30
        Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                cooldown -= 1
            }
        }
    }
}
