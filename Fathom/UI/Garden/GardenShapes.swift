import SwiftUI
import UIKit

// MARK: - Color adaptation

extension Color {
    /// Returns a copy with scaled saturation and a brightness delta (clamped 0...1).
    /// Used to derive the sky's ink from the app accent so it keeps proper
    /// contrast on whichever background the theme sets.
    func adjusted(saturationScale: CGFloat = 1, brightnessDelta: CGFloat = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(
            hue: Double(h),
            saturation: Double(min(max(s * saturationScale, 0), 1)),
            brightness: Double(min(max(b + brightnessDelta, 0), 1)),
            opacity: Double(a)
        )
    }
}

// MARK: - Doodle tiers
//
// Fathom's sky fills with hand-drawn doodles. How long you read on a given day
// decides which *tier* of doodle that day can earn — the bigger the night of
// reading, the grander the thing that appears in your sky. Within a tier the
// doodle is drawn from a shared pool (repeats across the year are fine and
// expected — the whole filled grid is the artwork, not each cell).

enum DoodleTier: Int, CaseIterable {
    case none = 0      // no reading that day → a quiet dot
    case glimpse       // tier 1 · a short read
    case settledIn     // tier 2 · you settled in
    case grandNight    // tier 3 · a long, grand night

    /// In-world name shown on the day-detail sheet — warm, never a metric.
    var title: String {
        switch self {
        case .none:       return "A quiet night"
        case .glimpse:    return "A glimpse"
        case .settledIn:  return "You settled in"
        case .grandNight: return "A grand night"
        }
    }

    /// Generous thresholds — the next tier should feel like a bonus you
    /// stumble into, never a bar you fell short of.
    static func tier(for duration: TimeInterval) -> DoodleTier {
        if duration <= 0 { return .none }
        if duration < 20 * 60 { return .glimpse }     // under ~20 min
        if duration < 45 * 60 { return .settledIn }   // ~20–45 min
        return .grandNight                            // ~45 min and up
    }

    /// Asset-catalog names for the doodles available at this tier.
    var pool: [String] {
        switch self {
        case .none:
            return []
        case .glimpse:
            return ["Spark", "SparkRing", "Star", "Stars", "StarsRing",
                    "Asteroid", "CrescentMoon", "RainyCloud"]
        case .settledIn:
            return ["Moon", "CrescentMoonRing", "Saturn", "Comet", "Telescope",
                    "Radar", "UFO", "Rainbow", "LightningCloud"]
        case .grandNight:
            return ["AquariusConstellation", "AriesConstellation", "CancerConstellation",
                    "CapricornConstellation", "GeminiConstellation", "LeoConstellation",
                    "LibraConstellation", "RandoConstellation", "SagittariusConstellation",
                    "ScorpioConstellation", "TaurusConstellation", "VirgoConstellation",
                    "Jupiter", "Sun"]
        }
    }
}

enum DoodleCatalog {
    /// Every doodle across all tiers — used to pre-register the Canvas symbols
    /// (each tinted template image is rendered once, then drawn many times).
    static let allAssetNames: [String] =
        DoodleTier.glimpse.pool + DoodleTier.settledIn.pool + DoodleTier.grandNight.pool

    /// Deterministic doodle for a given day — stable across re-renders but
    /// chaotic enough to avoid visible striping. Mixes day, duration, and a
    /// third constant so two adjacent days with the same reading time still
    /// land on different pool entries.
    static func assetName(forDayOfYear day: Int, duration: TimeInterval) -> String? {
        let pool = DoodleTier.tier(for: duration).pool
        guard !pool.isEmpty else { return nil }
        // XOR three independent terms so neither day nor duration dominates.
        let a = UInt64(bitPattern: Int64(day &* 2_654_435_761))
        let b = UInt64(bitPattern: Int64(Int(duration) &* 1_000_003))
        let c = (a ^ b ^ 0xDEAD_BEEF_CAFE_1337) &* 6_364_136_223_846_793_005
        let idx = Int(c >> 33) % pool.count
        return pool[abs(idx)]
    }

    /// A human phrase for a doodle, to read after "you spotted …".
    /// e.g. "a comet", "Saturn", "the Leo constellation".
    static func phrase(for name: String) -> String {
        switch name {
        case "Spark", "SparkRing":   return "a spark"
        case "Star":                 return "a star"
        case "Stars":                return "a scatter of stars"
        case "StarsRing":            return "a ring of stars"
        case "Asteroid":             return "an asteroid"
        case "CrescentMoon",
             "CrescentMoonRing":     return "a crescent moon"
        case "Moon":                 return "the moon"
        case "RainyCloud":           return "a rain cloud"
        case "LightningCloud":       return "a storm cloud"
        case "Rainbow":              return "a rainbow"
        case "Saturn":               return "Saturn"
        case "Jupiter":              return "Jupiter"
        case "Sun":                  return "the sun"
        case "Comet":                return "a comet"
        case "Telescope":            return "a telescope"
        case "Radar":                return "a radar dish"
        case "UFO":                  return "a UFO"
        case "RandoConstellation":   return "a constellation"
        default:
            if name.hasSuffix("Constellation") {
                let sign = name.replacingOccurrences(of: "Constellation", with: "")
                return "the \(sign) constellation"
            }
            return "something up there"
        }
    }
}

/// Deterministic pseudo-random value in 0..<1 from a cell seed + a salt.
/// Shared by the Canvas garden so per-day jitter/scale stays stable between
/// frames (and between renders) without any stored state.
func gardenRand(_ seed: Int, _ salt: Int) -> Double {
    var v = UInt64(bitPattern: Int64(seed &+ 1) &* 2_246_822_519)
    v ^= UInt64(bitPattern: Int64(salt &+ 1) &* 3_266_489_917)
    v = (v &* 2_654_435_761) & 0xFFFF_FFFF
    return Double(v % 1000) / 1000.0
}

// MARK: - Garden sprites
//
// Everything about a day's mark that *doesn't* change during the reveal is
// resolved once, up front, into a flat `GardenSprite` array. The Canvas draw
// loop then only applies the time-varying envelope (opacity/scale) per frame —
// no RNG, no catalog lookups, no layout math while the clock is ticking.

struct GardenSprite {
    enum Kind {
        /// A reading day: a tinted doodle symbol resolved by id from the Canvas.
        /// `hapticStrength` (0…1) scales the tick fired when it pops into view.
        case doodle(symbolID: String, hapticStrength: Float)
        /// A faint dot. *Every* day has one — they form the static grid that is
        /// painted immediately, and doodles bloom on top of the reading days.
        case dot(radius: CGFloat, opacity: Double)
    }

    let dayIndex: Int     // 0-based day of year this sprite represents
    let center: CGPoint   // final, jittered position
    let baseDim: CGFloat  // settled size before the pop envelope
    let radius: CGFloat   // hit-test radius around `center`
    /// When a doodle begins to bloom, as a fraction of the global reveal 0…1.
    /// Unused for dots (they are static).
    let bloomStart: Double
    /// How long a doodle takes to bloom, as a fraction of the reveal.
    let bloomSpan: Double
    let kind: Kind
}

enum GardenLayout {
    /// Cell geometry for the packed meadow grid.
    static func metrics(count: Int, size: CGSize, columns: Int)
        -> (cellW: CGFloat, cellH: CGFloat, rows: Int)
    {
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        return (size.width / CGFloat(columns), size.height / CGFloat(rows), rows)
    }

    /// The jittered centre for a cell — shared by the dot and the doodle of the
    /// same day so the doodle blooms exactly over its own dot.
    static func center(index: Int, cellW: CGFloat, cellH: CGFloat, columns: Int) -> CGPoint {
        let col = index % columns
        let row = index / columns
        let x = (CGFloat(col) + 0.5) * cellW + CGFloat(gardenRand(index, 4) - 0.5) * cellW * 0.4
        let y = (CGFloat(row) + 0.5) * cellH + CGFloat(gardenRand(index, 5) - 0.5) * cellH * 0.4
        return CGPoint(x: x, y: y)
    }

    /// Maps a point to a day index using the same plain grid the sprites are
    /// laid out on — a fast first pass; callers refine with sprite hit radii.
    static func cell(at point: CGPoint, count: Int, size: CGSize, columns: Int) -> Int? {
        let (cellW, cellH, rows) = metrics(count: count, size: size, columns: columns)
        let col = Int(point.x / cellW), row = Int(point.y / cellH)
        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }
        let index = row * columns + col
        return index < count ? index : nil
    }
}

/// The static dot for every day — depends only on the day count and size, *not*
/// on reading data, so it can be painted the instant the view appears (before
/// the durations have even loaded).
func buildDotGrid(count: Int, size: CGSize, columns: Int) -> [GardenSprite] {
    guard size.width > 0, size.height > 0, count > 0 else { return [] }
    let (cellW, cellH, _) = GardenLayout.metrics(count: count, size: size, columns: columns)
    let cell = min(cellW, cellH)

    var dots: [GardenSprite] = []
    dots.reserveCapacity(count)
    for index in 0..<count {
        let dotR = 1.0 + CGFloat(gardenRand(index, 2)) * 1.6
        dots.append(GardenSprite(
            dayIndex: index,
            center: GardenLayout.center(index: index, cellW: cellW, cellH: cellH, columns: columns),
            baseDim: dotR * 2,
            radius: max(dotR, cell * 0.3),
            bloomStart: 0,
            bloomSpan: 1,
            kind: .dot(radius: dotR, opacity: 0.12 + gardenRand(index, 3) * 0.16)
        ))
    }
    return dots
}

/// The blooming doodles — one per reading day. Built when the durations arrive
/// (or change), and overlaid on the dot grid.
func buildDoodleSprites(durations: [TimeInterval], size: CGSize, columns: Int) -> [GardenSprite] {
    guard size.width > 0, size.height > 0, !durations.isEmpty else { return [] }
    let (cellW, cellH, rows) = GardenLayout.metrics(count: durations.count, size: size, columns: columns)
    let cell = min(cellW, cellH)
    // Per-row reveal window; rows overlap so the wave stays continuous.
    let window = 0.3

    var sprites: [GardenSprite] = []
    for index in durations.indices {
        guard let name = DoodleCatalog.assetName(forDayOfYear: index + 1, duration: durations[index]) else {
            continue
        }
        let row = index / columns

        // Top-down sweep: each row starts a little after the one above it. A
        // small per-item phase jitter keeps a row from popping in lockstep.
        let rowStart = (Double(row) / Double(rows)) * (1 - window)
        let phase = gardenRand(index, 7) * window * 0.4
        let start = min(1 - window, rowStart + phase)

        // All doodles the same size — slightly larger than the cell so they feel
        // present without overlapping heavily.
        let baseDim = cell * 1.15

        // Doodles sit upright, centred on their cell — no jitter, no rotation —
        // so they read as a tidy, placed grid (the dots keep the organic scatter).
        let col = index % columns
        let row2 = index / columns
        let center = CGPoint(x: (CGFloat(col) + 0.5) * cellW, y: (CGFloat(row2) + 0.5) * cellH)

        // A grander doodle earns a firmer tick when it pops in.
        let strength: Float
        switch DoodleTier.tier(for: durations[index]) {
        case .grandNight: strength = 0.85
        case .settledIn:  strength = 0.6
        default:          strength = 0.4
        }

        sprites.append(GardenSprite(
            dayIndex: index,
            center: center,
            baseDim: baseDim,
            radius: baseDim * 0.5,
            bloomStart: start,
            bloomSpan: window,
            kind: .doodle(symbolID: name, hapticStrength: strength)
        ))
    }
    return sprites
}
