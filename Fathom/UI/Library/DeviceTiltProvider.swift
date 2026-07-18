import Combine
import CoreMotion
import SwiftUI

/// Publishes the device's tilt, for the parallax on search-result covers.
///
/// Uses `deviceMotion` rather than raw `accelerometer` data: it's already
/// fused with the gyroscope and gravity-referenced, so it doesn't jitter while
/// the phone is still and doesn't drift the way integrated gyro data does.
///
/// No usage-description key is required — attitude/accelerometer access is
/// unrestricted on iOS. (`NSMotionUsageDescription` covers pedometer and
/// activity data from CMMotionActivityManager, which this never touches.)
@MainActor
final class DeviceTiltProvider: ObservableObject {

    /// Left/right tilt in degrees, clamped and smoothed. Drives rotation about Y.
    @Published private(set) var roll: Double = 0
    /// Forward/back tilt in degrees, relative to how the phone is being held.
    @Published private(set) var pitch: Double = 0

    /// Beyond this the effect stops reading as depth and starts reading as a
    /// glitch, so tilt saturates rather than tracking the device 1:1.
    private let maxDegrees: Double = 22

    /// 30Hz is plenty — the covers are smoothed into the value anyway, and it
    /// halves the wake-ups of a 60Hz feed for no visible difference.
    private let updateInterval: TimeInterval = 1.0 / 30.0

    /// Low-pass factor. Raw device motion is subtly noisy even on a still
    /// phone; without this the covers shimmer when nobody is touching them.
    /// Higher = more responsive but closer to that noise floor.
    private let smoothing: Double = 0.18

    private let motionManager = CMMotionManager()

    /// The attitude when tracking started. Tilt is measured *relative* to this,
    /// so the covers sit flat at whatever angle you're already holding the
    /// phone — rather than being permanently skewed for anyone who reads lying
    /// down or with the phone flat on a desk.
    private var referenceRoll: Double?
    private var referencePitch: Double?

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func start() {
        guard motionManager.isDeviceMotionAvailable,
              !motionManager.isDeviceMotionActive
        else { return }

        referenceRoll = nil
        referencePitch = nil
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated {
                self.ingest(motion.attitude)
            }
        }
    }

    /// Must be called when the search surface closes. An unstopped motion
    /// manager keeps the sensors powered and the callback retained for the
    /// lifetime of the app.
    func stop() {
        motionManager.stopDeviceMotionUpdates()
        roll = 0
        pitch = 0
        referenceRoll = nil
        referencePitch = nil
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    private func ingest(_ attitude: CMAttitude) {
        if referenceRoll == nil {
            referenceRoll = attitude.roll
            referencePitch = attitude.pitch
        }
        guard let referenceRoll, let referencePitch else { return }

        let rawRoll = clamp((attitude.roll - referenceRoll) * 180 / .pi)
        let rawPitch = clamp((attitude.pitch - referencePitch) * 180 / .pi)

        roll += (rawRoll - roll) * smoothing
        pitch += (rawPitch - pitch) * smoothing
    }

    private func clamp(_ degrees: Double) -> Double {
        min(max(degrees, -maxDegrees), maxDegrees)
    }
}
