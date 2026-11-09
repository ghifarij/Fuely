import FuelyCore
import Foundation

/// A HealthKit stand-in for previews: a few weeks of plausible water, sleep and workouts before
/// today, so the week view and day detail have something to show. Never touches HealthKit.
/// Today's Fuely drinks come from the preview store, so this returns none for today.
struct PreviewHealthKit: HealthKitClient {
    let calendar: Calendar
    let now: Date

    @MainActor
    init() {
        calendar = PreviewData.calendar
        now = PreviewData.now
    }

    func requestAuthorization() async throws {}
    func waterWriteAccess() -> HealthAccessStatus { .allowed }
    func saveWater(_ entry: WaterEntry) async throws -> UUID { UUID() }
    func deleteWater(entryID: UUID) async throws {}

    func waterEntries(in interval: DateInterval) async throws -> [WaterEntry] {
        days(in: interval).flatMap { offset, day -> [WaterEntry] in
            var entries: [WaterEntry] = []
            if offset < 0 {
                let amounts = [[300, 500, 250, 400, 350, 300], [250, 250, 500], [400, 300, 500, 300, 250, 500, 300],
                               [500, 300, 250, 300]][abs(offset) % 4]
                for (index, amount) in amounts.enumerated() {
                    let date = day.addingTimeInterval(TimeInterval((7 + index * 2) * 3600 + 15 * 60))
                    entries.append(WaterEntry(id: Self.id(offset, index), date: date, amountML: amount, source: .fuely,
                                              healthKitSampleID: UUID()))
                }
            }
            if offset == 0 || abs(offset) % 3 == 1 {
                entries.append(WaterEntry(id: Self.id(offset, 99), date: day.addingTimeInterval(12.5 * 3600),
                                          amountML: 300, source: .external(name: "Other App")))
            }
            return entries.filter { interval.contains($0.date) && $0.date <= now }
        }
    }

    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        let watch = SleepSampleSource(bundleIdentifier: "com.apple.health.watch", isAppleWatch: true)
        return days(in: interval).flatMap { offset, day -> [SleepSample] in
            guard offset != -3 else { return [] } // a night without the Watch ("—")
            let wake = day.addingTimeInterval(TimeInterval(4 * 3600 + 45 * 60 + abs(offset % 3) * 10 * 60))
            let hours = [7.6, 6.4, 8.1, 7.0, 5.9][abs(offset) % 5]
            let start = wake.addingTimeInterval(-hours * 3600)
            if abs(offset) % 2 == 1 {
                let middle = start.addingTimeInterval(hours * 1800)
                return [SleepSample(start: start, end: middle, stage: .asleepCore, source: watch),
                        SleepSample(start: middle.addingTimeInterval(8 * 60), end: wake, stage: .asleepDeep, source: watch)]
            }
            return [SleepSample(start: start, end: wake, stage: .asleepCore, source: watch)]
        }
        .filter { $0.end > interval.start && $0.start < interval.end && $0.end <= now }
    }

    func workouts(in interval: DateInterval) async throws -> [WorkoutSample] {
        days(in: interval).compactMap { offset, day -> WorkoutSample? in
            let minutes = [55.0, 0, 30, 0, 62, 0, 0][abs(offset) % 7]
            guard minutes > 0 else { return nil }
            let start = day.addingTimeInterval(6 * 3600)
            return WorkoutSample(start: start, end: start.addingTimeInterval(minutes * 60), duration: minutes * 60)
        }
        .filter { interval.contains($0.start) && $0.start <= now }
    }

    /// (offset from today, start of day) for every day overlapping `interval`.
    private func days(in interval: DateInterval) -> [(Int, Date)] {
        let today = calendar.startOfDay(for: now)
        var result: [(Int, Date)] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            if offset <= 0 { result.append((offset, day)) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return result
    }

    private static func id(_ offset: Int, _ index: Int) -> UUID {
        let value = UInt64(bitPattern: Int64(offset)) &* 1000 &+ UInt64(index)
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llX", value & 0xFFFF_FFFF_FFFF))!
    }
}
