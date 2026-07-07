import SwiftUI
import Combine

extension Notification.Name {
    /// Posted after a reading session has been written to the store, so the
    /// observatory can refresh once the data is actually committed (no race).
    static let fathomReadingSessionLogged = Notification.Name("fathom.readingSessionLogged")
}

/// Drives the home-screen "observatory" — the little live indicator that makes
/// the Memory Garden an active part of the app. It reflects one of three states
/// derived from the user's reading activity:
///
/// - `.idle`      — nothing read today and nothing waiting; a quiet resting sky.
/// - `.spotting`  — you read today; tonight's doodle is being "found" (it's
///                  awarded the next day, so today it's still being spotted).
/// - `.pending`   — a past day earned a doodle you haven't revealed yet.
@MainActor
final class ObservatoryViewModel: ObservableObject {
    enum Phase: Equatable { case idle, spotting, pending }

    @Published private(set) var phase: Phase = .idle
    /// The doodle waiting to be revealed (set when `.pending`) — used by the
    /// Phase 2 reveal ceremony.
    @Published private(set) var pendingDoodle: String?
    @Published private(set) var pendingDayKey: String?
    @Published private(set) var pendingDuration: TimeInterval = 0

    private let repository: BookRepository
    static let lastRevealedKey = "memoryGarden.lastRevealedDay"

    init(repository: BookRepository) {
        self.repository = repository
    }

    func refresh() async {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let raw = await repository.listReadingActivity(forYear: year)

        // Total minutes per day.
        var byDate: [String: TimeInterval] = [:]
        for activity in raw { byDate[activity.date, default: 0] += activity.duration }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let todayKey = formatter.string(from: now)

        let readToday = (byDate[todayKey] ?? 0) > 0

        // Most recent *past* day that earned a doodle.
        let lastReadDay = byDate
            .filter { $0.key < todayKey && $0.value > 0 }
            .keys.max()

        let lastRevealed = UserDefaults.standard.string(forKey: Self.lastRevealedKey)
        let isPending: Bool = {
            guard let lastReadDay else { return false }
            guard let lastRevealed else { return true }   // never revealed anything yet
            return lastReadDay > lastRevealed
        }()

        if isPending, let lastReadDay, let date = formatter.date(from: lastReadDay) {
            let doy = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            let mins = byDate[lastReadDay] ?? 0
            pendingDoodle = DoodleCatalog.assetName(forDayOfYear: doy, duration: mins)
            pendingDayKey = lastReadDay
            pendingDuration = mins
            phase = .pending
        } else if readToday {
            pendingDoodle = nil
            pendingDayKey = nil
            pendingDuration = 0
            phase = .spotting
        } else {
            pendingDoodle = nil
            pendingDayKey = nil
            pendingDuration = 0
            phase = .idle
        }
    }
}
