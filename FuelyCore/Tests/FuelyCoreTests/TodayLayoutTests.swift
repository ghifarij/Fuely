import Foundation
import Testing
@testable import FuelyCore

@Suite struct TodayDrinkRowTests {
    private let cal = Calendar.test()

    @Test func nothingTodayShowsTheEmptyRowAndNoShowAll() {
        let row = TodayDrinkRow(entries: [], externalML: 0)
        #expect(row == .none)
        #expect(!row.showsAll)
    }

    @Test func newestFuelyEntryWinsWhateverTheOrder() {
        let early = WaterEntry(date: cal.at(2026, 11, 10, 8), amountML: 250)
        let late = WaterEntry(date: cal.at(2026, 11, 10, 13, 30), amountML: 500)
        let middle = WaterEntry(date: cal.at(2026, 11, 10, 11), amountML: 150)
        #expect(TodayDrinkRow(entries: [early, late, middle], externalML: 0) == .fuely(late))
        #expect(TodayDrinkRow(entries: [late, middle, early], externalML: 0) == .fuely(late))
    }

    @Test func fuelyEntryWinsOverOtherAppsWater() {
        let entry = WaterEntry(date: cal.at(2026, 11, 10, 9), amountML: 250)
        let row = TodayDrinkRow(entries: [entry], externalML: 800)
        #expect(row == .fuely(entry))
        #expect(row.showsAll)
    }

    @Test func otherAppsOnlyShowsTheReadOnlyRow() {
        let row = TodayDrinkRow(entries: [], externalML: 300)
        #expect(row == .otherApps(ml: 300))
        #expect(row.showsAll)
    }

    @Test func singleDrinkStillOffersShowAll() {
        let entry = WaterEntry(date: cal.at(2026, 11, 10, 9), amountML: 250)
        #expect(TodayDrinkRow(entries: [entry], externalML: 0).showsAll)
    }

    @Test func negativeOtherAppsWaterCountsAsNone() {
        #expect(TodayDrinkRow(entries: [], externalML: -50) == .none)
    }
}

@Suite struct TodayLayoutTests {
    @Test func regularScreensKeepTheScaledDropCappedAt220() {
        #expect(TodayLayout.dropHeight(scaledHeight: 176, screenHeight: 874) == 176)
        #expect(TodayLayout.dropHeight(scaledHeight: 200, screenHeight: 956) == 200)
        #expect(TodayLayout.dropHeight(scaledHeight: 300, screenHeight: 874) == 220)
    }

    @Test func shortScreensShrinkTheDrop() {
        // 4.7" iPhone SE (375 × 667 pt).
        #expect(TodayLayout.dropHeight(scaledHeight: 176, screenHeight: 667) == 140)
    }

    @Test func shortScreensStillScaleWithDynamicTypeUpToTheirOwnCap() {
        let larger = TodayLayout.dropHeight(scaledHeight: 198, screenHeight: 667)
        #expect(larger > 140 && larger < 198)
        #expect(TodayLayout.dropHeight(scaledHeight: 400, screenHeight: 667) == TodayLayout.compactMaxDropHeight)
    }

    @Test func thresholdIsInclusiveOfTheShortScreenLimit() {
        let limit = TodayLayout.shortScreenMaxHeight
        #expect(TodayLayout.isShortScreen(height: limit))
        #expect(!TodayLayout.isShortScreen(height: limit + 1))
    }

    @Test func unknownHeightKeepsTheRegularDrop() {
        #expect(TodayLayout.dropHeight(scaledHeight: 176, screenHeight: 0) == 176)
    }
}
