import SwiftUI

struct AuthFlowView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.appTheme) var theme

    let homeViewModel: HomeViewModel
    let libraryViewModel: LibraryViewModel
    let bookRepository: BookRepository
    let vocabularyRepo: VocabularyRepository

    @State private var sentEmail: String? = nil

    var body: some View {
        Group {
            // Accounts off (v1): straight into the app. This must precede the
            // `isLoading` branch — `startListening` is what clears that flag,
            // and it never runs while the flag is off.
            if !FeatureFlags.accountsEnabled {
                RootView(
                    homeViewModel: homeViewModel,
                    libraryViewModel: libraryViewModel,
                    bookRepository: bookRepository,
                    vocabularyRepo: vocabularyRepo
                )
            } else if authService.isLoading {
                theme.colors.background
                    .ignoresSafeArea()
            } else if authService.session != nil {
                RootView(
                    homeViewModel: homeViewModel,
                    libraryViewModel: libraryViewModel,
                    bookRepository: bookRepository,
                    vocabularyRepo: vocabularyRepo
                )
                .transition(.opacity)
            } else {
                authFlow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.isLoading)
        .animation(.easeInOut(duration: 0.3), value: authService.session != nil)
        // Reset sign-in flow when user signs out so email entry is fresh
        .onChange(of: authService.session == nil) { _, signedOut in
            if signedOut { sentEmail = nil }
        }
    }

    private var authFlow: some View {
        ZStack {
            if let email = sentEmail {
                MagicLinkSentView(
                    email: email,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) { sentEmail = nil }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                EmailEntryView(onSent: { email in
                    withAnimation(.easeInOut(duration: 0.3)) { sentEmail = email }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
    }
}
