import SwiftUI

// MARK: - AboutScreen

struct AboutScreen: View {
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    private var appName: String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "Fathom"
    }

    var body: some View {
        List {
            Section {
                heroRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            Section {
                LabeledContent("Version") {
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section {
                Link(destination: URL(string: "https://fathom.read/privacy")!) {
                    ProfileRow(icon: "hand.raised.fill",
                                iconColor: Color(.systemBlue),
                                title: "Privacy Policy")
                }
                Link(destination: URL(string: "https://fathom.read/terms")!) {
                    ProfileRow(icon: "doc.text.fill",
                                iconColor: Color(.systemGray),
                                title: "Terms of Service")
                }
                Link(destination: URL(string: "mailto:support@fathom.read")!) {
                    ProfileRow(icon: "envelope.fill",
                                iconColor: Color(.systemGreen),
                                title: "Contact Support")
                }
            } header: {
                SectionHeader("Legal & Support")
            }

            Section {
                NavigationLink {
                    AcknowledgmentsScreen()
                } label: {
                    ProfileRow(icon: "heart.fill",
                                iconColor: Color(.systemPink),
                                title: "Acknowledgments")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("Made with ♥ for readers")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }

    private var heroRow: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "5B7CB0"),
                                Color(hex: "4A9D8E")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color(hex: "5B7CB0").opacity(0.3), radius: 16, y: 6)
                Image(systemName: "book.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(appName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("A thoughtful reader")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
