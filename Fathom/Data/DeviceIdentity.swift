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
/// Minted once and persisted, then anchored to `identifierForVendor` so a
/// device-to-device transfer can be detected and the id re-minted — otherwise
/// both phones inherit the same id and their reading time overwrites rather
/// than sums.
///
/// It does not survive deleting and reinstalling the app, and a re-mint
/// likewise leaves the previous id behind. Both are harmless: the old rows stay
/// as read-only history under an id nothing writes to any more, and totals are
/// a sum, so they still count.
nonisolated enum DeviceIdentity {

    private static let defaultsKey = "fathom.deviceID"
    /// The `identifierForVendor` this id was minted under. Stored so a change
    /// of hardware can be detected — see `current`.
    private static let vendorKey = "fathom.deviceID.vendorID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// This device's identifier. Stable for the lifetime of the installation,
    /// and re-minted if the app finds itself on different hardware.
    ///
    /// The re-mint is the important part. A device-to-device transfer copies
    /// `UserDefaults` along with everything else, so without it both phones
    /// claim the same id, write to the same `(bookID, date, deviceID)` row, and
    /// overwrite each other's reading time instead of summing it — exactly the
    /// under-reporting the per-device key exists to prevent.
    ///
    /// `identifierForVendor` is the signal: it is per-device, so it differs on
    /// the receiving phone after a transfer.
    static var current: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        let defaults = UserDefaults.standard
        let vendor = vendorID()
        let stored = defaults.string(forKey: defaultsKey)

        if let stored, !stored.isEmpty {
            guard let vendor else {
                // `identifierForVendor` is nil before first unlock. Keep what
                // we have rather than minting an id we cannot anchor; the check
                // runs again on a later launch.
                cached = stored
                return stored
            }
            if defaults.string(forKey: vendorKey) == vendor {
                cached = stored
                return stored
            }
            // Either the hardware changed, or this install predates the anchor
            // and a transfer cannot be ruled out. Re-mint either way: a wrong
            // re-mint only orphans this device's existing rows as history,
            // which still sum correctly, while a missed one silently loses
            // reading time.
            AppLogger.log(tag: "DeviceIdentity",
                          "Hardware identity changed — re-minting device id")
        }

        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        if let vendor { defaults.set(vendor, forKey: vendorKey) }
        cached = fresh
        return fresh
    }

    private static func vendorID() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
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
