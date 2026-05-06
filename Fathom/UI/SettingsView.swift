import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.appTheme) var theme

    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                dangerSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your library.")
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if let email = authService.session?.user.email {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondary)
                        Text(email)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.primary)
                    }
                } icon: {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "4A7DB5"))
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}
