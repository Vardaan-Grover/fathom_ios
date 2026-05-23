import SwiftUI

struct MemoryGardenView: View {
    @StateObject private var viewModel: MemoryGardenViewModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var isVisible = false
    let brightBlue = Color(red: 0.1, green: 0.05, blue: 0.85)

    let year: Int
    let daysInYear: [Date]

    init(
        year: Int = Calendar.current.component(.year, from: Date()), bookRepository: BookRepository
    ) {
        self.year = year
        self._viewModel = StateObject(
            wrappedValue: MemoryGardenViewModel(bookRepository: bookRepository))

        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        // Generate 365 days (or 366 for leap years, but simple 365 for UI is fine)
        let days = (0..<365).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startOfYear)
        }
        self.daysInYear = days
    }

    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 19)

    var body: some View {
        VStack {
            ZStack {
                Text(String(year))
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(brightBlue)
                    .clipShape(Capsule())

                HStack {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(brightBlue)
                        .frame(width: 32, height: 32)
                        .onTapGesture {
                            dismiss()
                        }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.dailyActivities.isEmpty {
                VStack(spacing: 12) {
                    Text("Your garden is empty.")
                        .foregroundColor(theme.colors.secondary)
                    Button("Plant Some Seeds (Mock Data)") {
                        Task {
                            await viewModel.injectMockData(year: year)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(theme.colors.shelfAccent)
                }
                .padding()
            } else {
                ZStack {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(daysInYear.enumerated()), id: \.offset) { index, date in
                            let dateStr = formatter.string(from: date)
                            let activity = viewModel.dailyActivities[dateStr]

                            GardenCell(
                                date: date,
                                activity: activity,
                                variation: index,  // Use index for deterministic variation
                                isVisible: isVisible,
                                delay: Double(index) * 0.005,  // Staggered animation delay
                                color: brightBlue
                            )
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.bottom, 80)
                }
            }
            Spacer(minLength: 0)
        }
        .navigationBarBackButtonHidden()
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            Task {
                await viewModel.load(forYear: year)
            }
            // Trigger load animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation {
                    isVisible = true
                }
            }
        }
    }

    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    struct GardenCell: View {
        let date: Date
        let activity: DailyActivity?
        let variation: Int
        let isVisible: Bool
        let delay: Double
        let color: Color

        @Environment(\.appTheme) private var theme

        @State private var hasAppeared = false

        var body: some View {
            let duration = activity?.duration ?? 0
            let category = GardenShapeCategory.category(for: duration)

            GardenShapeView(category: category, variation: variation, color: color)
                .frame(width: 16, height: 16)
                // Staggered load animation
                .scaleEffect(hasAppeared ? 1.0 : 0.0)
                .opacity(hasAppeared ? 1.0 : 0.0)
                .onAppear {
                    if isVisible {
                        triggerAnimation()
                    }
                }
                .onChange(of: isVisible) { _, newValue in
                    if newValue {
                        triggerAnimation()
                    }
                }
        }

        private func triggerAnimation() {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(delay)) {
                hasAppeared = true
            }
        }
    }
}
