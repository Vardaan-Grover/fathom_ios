import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A stable identifier for this installation, used to partition data that
/// accumulates per device.
///
/// `ReadingActivity` is the reason this exists. Reading time is additive: a day
/// spent 20 minutes on an iPhone and 15 on an iPad is 35 minutes, and any
/// scheme where two devices merge into one shared row has to pick between
/// double-counting and losing a session. Giving each device its own row removes
/// the merge entirely — nobody writes anybody else's row, so the total is just
/// a sum. See §3.4 of docs/sync-conflict-policy.md.
///
/// Seeded from `identifierForVendor` where available and then persisted, so it
/// survives the cases where that API returns nil (notably before first unlock).
/// It does not survive deleting and reinstalling the app: the old device's rows
/// stay in the zone as read-only history under an ID nothing writes to any
/// more. That is harmless — orphaned rows are still summed, so totals stay
/// correct; the app simply stops adding to them.
nonisolated enum DeviceIdentity {

    private static let defaultsKey = "fathom.deviceID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// This device's identifier. Stable for the lifetime of the installation.
    static var current: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        if let stored = UserDefaults.standard.string(forKey: defaultsKey), !stored.isEmpty {
            cached = stored
            return stored
        }

        let fresh = makeIdentifier()
        UserDefaults.standard.set(fresh, forKey: defaultsKey)
        cached = fresh
        return fresh
    }

    private static func makeIdentifier() -> String {
        #if canImport(UIKit)
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return vendorID
        }
        #endif
        return UUID().uuidString
    }

    /// Test seam. Not for production use — changing the identifier mid-life
    /// orphans this device's existing rows.
    static func overrideForTesting(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        cached = value
        if let value {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
