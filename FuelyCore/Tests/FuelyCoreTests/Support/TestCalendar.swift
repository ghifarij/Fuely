import Foundation
@testable import FuelyCore

extension Calendar {
    /// Gregorian calendar in a fixed time zone. Uses en_US so `firstWeekday` is Sunday,
    /// which proves the core logic forces a Monday week on its own.
    static func test(_ timeZone: String = "Asia/Bangkok") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}

extension TimeInterval {
    static func minutes(_ value: Double) -> TimeInterval { value * 60 }
    static func hours(_ value: Double) -> TimeInterval { value * 3600 }
}
