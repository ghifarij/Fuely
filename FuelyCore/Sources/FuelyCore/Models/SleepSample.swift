import Foundation

/// Sleep analysis stages, mirroring HealthKit's `HKCategoryValueSleepAnalysis`.
public enum SleepStage: String, Codable, Sendable, Hashable, CaseIterable {
    case inBed, awake, asleepUnspecified, asleepCore, asleepDeep, asleepREM

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        }
    }

    /// Core, deep or REM: the stages an Apple Watch records (iOS 16+), unlike plain "asleep".
    public var isStaged: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake, .asleepUnspecified: false
        }
    }
}

/// Where a sleep sample came from (HealthKit's `HKSourceRevision`).
public struct SleepSampleSource: Codable, Sendable, Hashable {
    public var bundleIdentifier: String?
    /// Recorded by an Apple Watch (`productType` starts with "Watch").
    public var isAppleWatch: Bool
    /// The source's display name (e.g. "Apple Watch").
    public var name: String?

    public init(bundleIdentifier: String?, isAppleWatch: Bool, name: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.isAppleWatch = isAppleWatch
        self.name = name
    }

    /// The name, else the bundle id, else "Unknown".
    public var displayName: String { name ?? bundleIdentifier ?? "Unknown" }

    public static let unknown = SleepSampleSource(bundleIdentifier: nil, isAppleWatch: false)
}

/// One sleep analysis sample. Samples from several sources may overlap.
public struct SleepSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var source: SleepSampleSource

    public init(start: Date, end: Date, stage: SleepStage, source: SleepSampleSource = .unknown) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }
}
