import SwiftUI
import UserNotifications

// MARK: - NotificationSettingsScreen

struct NotificationSettingsScreen: View {
    @State private var isEnabled: Bool = NotificationSettingsStore.shared.isEnabled
    @State private var time: Date = NotificationSettingsStore.shared.timeAsDate
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(.systemRed))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color(.systemRed).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        Text("Daily Reading Reminder")
                    }
                }
                .disabled(working || authStatus == .denied)

                if isEnabled {
                    DatePicker(
                        "Time",
                        selection: $time,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: time) { _, newValue in
                        Task {
                            let cal = Calendar.current
                            let comps = cal.dateComponents([.hour, .minute], from: newValue)
                            await NotificationSettingsStore.shared.setTime(
                                hour: comps.hour ?? 20,
                                minute: comps.minute ?? 0
                            )
                        }
                    }
                }
            } header: {
                SectionHeader("Daily")
            } footer: {
                footerText
            }

            if authStatus == .denied {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                    }
                } footer: {
                    Text("Notifications are turned off for Fathom in iOS Settings.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isEnabled)
        .task {
            authStatus = await NotificationSettingsStore.shared.authorizationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NotificationSettingsStore.didChangeNotification)
        ) { _ in
            isEnabled = NotificationSettingsStore.shared.isEnabled
            time = NotificationSettingsStore.shared.timeAsDate
        }
    }

    @ViewBuilder
    private var footerText: some View {
        if authStatus == .denied {
            Text("Enable notifications for Fathom in iOS Settings to receive a daily reminder.")
        } else if isEnabled {
            Text("You'll get a gentle reminder once a day to pick up your current book.")
        } else {
            Text("Get a daily nudge to read at a time that works for you.")
        }
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                working = true
                Task {
                    let active = await NotificationSettingsStore.shared.setEnabled(newValue)
                    isEnabled = active
                    authStatus = await NotificationSettingsStore.shared.authorizationStatus()
                    working = false
                }
            }
        )
    }
}
