import SwiftUI
import Auth

// MARK: - ProfileView
//
// The main Profile screen. Hero profile card + grouped sections for
// Library, Appearance, Vocabulary, Notifications, Sync & Storage, Data,
// About, and Account.

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.appTheme) private var theme

    let bookRepository: BookRepository

    // Profile state
    @State private var profile: UserProfile = UserProfileStore.shared.load()

    // Sheets
    @State private var showAvatarPicker = false
    @State private var showNameEditor = false

    // Sign out
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                profileSection
                memoryGardenSection
                librarySection
                appearanceSection
                vocabularySection
                notificationsSection
                syncStorageSection
                dataSection
                aboutSection
                signOutSection
            }
            .listSectionSpacing(.compact)
            .contentMargins(.bottom, 90, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showAvatarPicker) {
            EmojiAvatarPickerSheet(
                initialEmoji: profile.avatarEmoji,
                initialColorHex: profile.avatarColorHex,
                initials: UserProfile.initials(
                    displayName: profile.displayName,
                    email: authService.session?.user.email
                ),
                onSave: { newEmoji, newHex in
                    profile.avatarEmoji = newEmoji
                    profile.avatarColorHex = newHex
                    UserProfileStore.shared.save(profile)
                }
            )
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(name: bindingForName())
        }
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
        .onReceive(
            NotificationCenter.default.publisher(for: UserProfileStore.didChangeNotification)
        ) { _ in
            profile = UserProfileStore.shared.load()
        }
    }

    private var profileSection: some View {
        Section {
            ProfileHeaderCard(
                profile: profile,
                email: authService.session?.user.email,
                onTapAvatar: { showAvatarPicker = true },
                onTapName: { showNameEditor = true }
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
    }

    private var memoryGardenSection: some View {
        Section {
            NavigationLink {
                MemoryGardenView(bookRepository: bookRepository)
            } label: {
                ProfileRow(
                    icon: "leaf.fill",
                    iconColor: Color(red: 0.1, green: 0.05, blue: 0.85),
                    title: "Memory Garden"
                )
            }
        } header: {
            SectionHeader("Journey")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var librarySection: some View {
        Section {
            NavigationLink {
                AllFinishedBooksScreen(bookRepository: bookRepository)
            } label: {
                ProfileRow(
                    icon: "checkmark.seal.fill",
                    iconColor: theme.colors.shelfAccent,
                    title: "Books I've Read"
                )
            }

            NavigationLink {
                AllHighlightsScreen()
            } label: {
                ProfileRow(
                    icon: "highlighter",
                    iconColor: .yellow,
                    title: "All Highlights"
                )
            }

            NavigationLink {
                AllNotesScreen()
            } label: {
                ProfileRow(
                    icon: "note.text",
                    iconColor: Color(.systemIndigo),
                    title: "All Notes"
                )
            }

            NavigationLink {
                AllBookmarksScreen()
            } label: {
                ProfileRow(
                    icon: "bookmark.fill",
                    iconColor: Color(red: 0.78, green: 0.08, blue: 0.15),
                    title: "All Bookmarks"
                )
            }
        } header: {
            SectionHeader("Library")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearancePickerScreen(selection: appearanceBinding)
            } label: {
                ProfileRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: Color(.systemPurple),
                    title: "Appearance",
                    trailing: appearanceBinding.wrappedValue.displayName
                )
            }

        } header: {
            SectionHeader("Appearance")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                VocabularyPreferencesScreen()
            } label: {
                ProfileRow(
                    icon: "character.book.closed.fill",
                    iconColor: Color(.systemTeal),
                    title: "Pronunciation"
                )
            }
        } header: {
            SectionHeader("Vocabulary")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                NotificationPreferencesScreen()
            } label: {
                ProfileRow(
                    icon: "bell.fill",
                    iconColor: Color(.systemRed),
                    title: "Notifications"
                )
            }
        } header: {
            SectionHeader("Notifications")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var syncStorageSection: some View {
        Section {
            ICloudSyncStatusRow()

            NavigationLink {
                StorageUsageScreen()
            } label: {
                ProfileRow(
                    icon: "internaldrive.fill",
                    iconColor: Color(.systemGray),
                    title: "Storage"
                )
            }
        } header: {
            SectionHeader("Sync & Storage")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                ExportDataScreen()
            } label: {
                ProfileRow(
                    icon: "square.and.arrow.up.fill",
                    iconColor: Color(.systemGreen),
                    title: "Export My Data"
                )
            }
        } header: {
            SectionHeader("Data")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutScreen()
            } label: {
                ProfileRow(
                    icon: "info.circle.fill",
                    iconColor: Color(.systemBlue),
                    title: "About"
                )
            }
        } header: {
            SectionHeader("Help")
        }
        .listRowBackground(theme.colors.surface)
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
        }
        .listRowBackground(theme.colors.surface)
    }

    // MARK: - Bindings

    private func bindingForName() -> Binding<String> {
        Binding(
            get: { profile.displayName ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.displayName = trimmed.isEmpty ? nil : trimmed
                UserProfileStore.shared.save(profile)
            }
        )
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: {
                switch themeManager.colorSchemeOverride {
                case .light: return .light
                case .dark: return .dark
                default: return .system
                }
            },
            set: { newValue in
                switch newValue {
                case .system: themeManager.colorSchemeOverride = nil
                case .light: themeManager.colorSchemeOverride = .light
                case .dark: themeManager.colorSchemeOverride = .dark
                }
            }
        )
    }
}

// MARK: - AppearanceMode

enum AppearanceMode: Hashable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
}

// MARK: - AppearancePickerScreen

struct AppearancePickerScreen: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        Form {
            Section {
                ForEach([AppearanceMode.system, .light, .dark], id: \.self) { mode in
                    HStack {
                        Text(mode.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selection = mode
                    }
                }
            } footer: {
                Text("Choose how Fathom looks. \"System\" follows your device's appearance.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }
}

// MARK: - ProfileRow

struct ProfileRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

            Text(title)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .kerning(0.4)
            .textCase(.uppercase)
    }
}
