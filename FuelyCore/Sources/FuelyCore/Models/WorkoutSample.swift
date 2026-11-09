import Foundation

/// One workout of any type (DECISIONS K1).
public struct WorkoutSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    /// Active duration in seconds (HealthKit's `HKWorkout.duration`, which excludes pauses).
    public var duration: TimeInterval

    public init(start: Date, end: Date, duration: TimeInterval) {
        self.start = start
        self.end = end
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, duration
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decodeIfPresent(Date.self, forKey: .start) ?? .distantPast
        self.init(start: start, end: try c.decodeIfPresent(Date.self, forKey: .end) ?? start,
                  duration: try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0)
    }
}
