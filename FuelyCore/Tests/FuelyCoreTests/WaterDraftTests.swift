import Foundation
import Testing
@testable import FuelyCore

/// The in-widget amount picker (DECISIONS W6b).
@Suite struct WaterDraftTests {
    let cal = Calendar.test()
    var now: Date { cal.at(2026, 11, 9, 14) }

    private func settings(widgetAmount: Int = 250) -> FuelySettings {
        var settings = FuelySettings.default
        settings.widgetAmountML = widgetAmount
        return settings
    }

    @Test func limitsSitNextToSettingsLimits() {
        #expect(SettingsLimits.widgetDraftML == 50...2000)
        #expect(SettingsLimits.widgetDraftStepML == 50)
        #expect(WaterDraft.lifetime == 120)
    }

    // MARK: Start

    @Test func startUsesTheSettingsWidgetAmount() {
        let draft = WaterDraft.start(settings: settings(widgetAmount: 350), now: now)
        #expect(draft == WaterDraft(amountML: 350, startedAt: now))
    }

    @Test func startClampsTheAmountIntoTheDraftRange() {
        #expect(WaterDraft.start(settings: settings(widgetAmount: 10), now: now).amountML == 50)
        #expect(WaterDraft.start(settings: settings(widgetAmount: 9000), now: now).amountML == 2000)
    }

    // MARK: Expiry

    @Test func activeForTwoMinutesThenStale() {
        let draft = WaterDraft(amountML: 250, startedAt: now)
        #expect(draft.expiresAt == now.addingTimeInterval(120))
        #expect(draft.isActive(at: now))
        #expect(draft.isActive(at: now.addingTimeInterval(119)))
        #expect(!draft.isActive(at: now.addingTimeInterval(120)))
        #expect(!draft.isActive(at: now.addingTimeInterval(3600)))
    }

    @Test func aDraftFromTheFutureIsStale() {
        // Clock moved back (or a corrupted file): never stay stuck in editing.
        let draft = WaterDraft(amountML: 250, startedAt: now.addingTimeInterval(600))
        #expect(!draft.isActive(at: now))
    }

    @Test func activeFiltersStaleDrafts() {
        let draft = WaterDraft(amountML: 250, startedAt: now)
        #expect(WaterDraft.active(draft, at: now.addingTimeInterval(60)) == draft)
        #expect(WaterDraft.active(draft, at: now.addingTimeInterval(121)) == nil)
        #expect(WaterDraft.active(nil, at: now) == nil)
    }

    // MARK: Step / clamp / set

    @Test func adjustStepsAndClamps() {
        let draft = WaterDraft(amountML: 250, startedAt: now)
        #expect(draft.adjusted(by: 50).amountML == 300)
        #expect(draft.adjusted(by: -50).amountML == 200)
        #expect(WaterDraft(amountML: 50, startedAt: now).adjusted(by: -50).amountML == 50)
        #expect(WaterDraft(amountML: 2000, startedAt: now).adjusted(by: 50).amountML == 2000)
    }

    @Test func adjustSnapsOffGridAmountsToTheStep() {
        // A Settings amount can only be a multiple of 50, but a stored file might not be.
        #expect(WaterDraft(amountML: 230, startedAt: now).adjusted(by: 50).amountML == 250)
        #expect(WaterDraft(amountML: 230, startedAt: now).adjusted(by: -50).amountML == 200)
    }

    @Test func clampRange() {
        #expect(WaterDraft.clamp(0) == 50)
        #expect(WaterDraft.clamp(-100) == 50)
        #expect(WaterDraft.clamp(2050) == 2000)
        #expect(WaterDraft.clamp(400) == 400)
    }

    @Test func canStepTellsTheButtonsWhenToDim() {
        #expect(!WaterDraft(amountML: 50, startedAt: now).canDecrease)
        #expect(WaterDraft(amountML: 50, startedAt: now).canIncrease)
        #expect(!WaterDraft(amountML: 2000, startedAt: now).canIncrease)
        #expect(WaterDraft(amountML: 250, startedAt: now).canDecrease)
    }

    // MARK: Presets

    @Test func presets() {
        #expect(WaterDraft.presetsML == [150, 250, 500])
        #expect(WaterDraft.circlePresetsML == [150, 250, 400, 500])
    }

    @Test func circleCyclesPresets() {
        let order = [150, 250, 400, 500, 150]
        for (from, to) in zip(order, order.dropFirst()) {
            #expect(WaterDraft.nextCirclePreset(after: from) == to)
        }
    }

    @Test func circleCycleFromAnOffPresetAmountGoesToTheNextLargerPreset() {
        #expect(WaterDraft.nextCirclePreset(after: 50) == 150)
        #expect(WaterDraft.nextCirclePreset(after: 300) == 400)
        #expect(WaterDraft.nextCirclePreset(after: 450) == 500)
        #expect(WaterDraft.nextCirclePreset(after: 750) == 150)
    }

    // MARK: Changes (what each widget button does)

    @Test func startFromIdle() {
        let draft = WaterDraft.apply(.start, to: nil, settings: settings(), now: now)
        #expect(draft == WaterDraft(amountML: 250, startedAt: now))
    }

    @Test func startWhileEditingRestartsFromTheSettingsAmount() {
        let old = WaterDraft(amountML: 800, startedAt: now.addingTimeInterval(-30))
        #expect(WaterDraft.apply(.start, to: old, settings: settings(), now: now) == WaterDraft(amountML: 250, startedAt: now))
    }

    @Test func eachTapRestartsTheTwoMinutes() {
        let old = WaterDraft(amountML: 250, startedAt: now.addingTimeInterval(-100))
        let later = now
        #expect(WaterDraft.apply(.adjust(50), to: old, settings: settings(), now: later) == WaterDraft(amountML: 300, startedAt: later))
        #expect(WaterDraft.apply(.set(500), to: old, settings: settings(), now: later) == WaterDraft(amountML: 500, startedAt: later))
        #expect(WaterDraft.apply(.cyclePreset, to: old, settings: settings(), now: later) == WaterDraft(amountML: 400, startedAt: later))
    }

    @Test func setClamps() {
        let draft = WaterDraft(amountML: 250, startedAt: now)
        #expect(WaterDraft.apply(.set(5000), to: draft, settings: settings(), now: now)?.amountML == 2000)
        #expect(WaterDraft.apply(.set(0), to: draft, settings: settings(), now: now)?.amountML == 50)
    }

    @Test func cancelReturnsToIdle() {
        let draft = WaterDraft(amountML: 250, startedAt: now)
        #expect(WaterDraft.apply(.cancel, to: draft, settings: settings(), now: now) == nil)
        #expect(WaterDraft.apply(.cancel, to: nil, settings: settings(), now: now) == nil)
    }

    @Test func editsOnAStaleOrMissingDraftAreIdle() {
        let stale = WaterDraft(amountML: 250, startedAt: now.addingTimeInterval(-121))
        for change in [WaterDraft.Change.adjust(50), .adjust(-50), .set(500), .cyclePreset] {
            #expect(WaterDraft.apply(change, to: stale, settings: settings(), now: now) == nil)
            #expect(WaterDraft.apply(change, to: nil, settings: settings(), now: now) == nil)
        }
    }

    // MARK: Commit

    @Test func commitLogsTheActiveDraftAmount() {
        let draft = WaterDraft(amountML: 400, startedAt: now)
        #expect(WaterDraft.amountToCommit(draft, now: now.addingTimeInterval(30)) == 400)
    }

    @Test func commitOnAStaleOrMissingDraftLogsNothing() {
        let stale = WaterDraft(amountML: 400, startedAt: now.addingTimeInterval(-121))
        #expect(WaterDraft.amountToCommit(stale, now: now) == nil)
        #expect(WaterDraft.amountToCommit(nil, now: now) == nil)
    }

    // MARK: Codable

    @Test func roundTripsThroughJSON() throws {
        let draft = WaterDraft(amountML: 300, startedAt: now)
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(WaterDraft.self, from: data) == draft)
    }
}

/// The draft in the App Group store and the work behind the picker's intents.
@Suite struct WaterDraftStoreTests {
    let cal = Calendar.test()
    let store = makeTempStore()
    var now: Date { cal.at(2026, 11, 9, 14) }

    @Test func noDraftByDefault() throws {
        #expect(try store.waterDraft() == nil)
        #expect(try store.activeWaterDraft(now: now) == nil)
    }

    @Test func applyWritesAndClearsTheDraft() throws {
        let started = try WaterDraftAction.apply(.start, store: store, now: now, reload: false)
        #expect(started == WaterDraft(amountML: 250, startedAt: now))
        #expect(try store.waterDraft() == started)

        let bigger = try WaterDraftAction.apply(.adjust(50), store: store, now: now.addingTimeInterval(5), reload: false)
        #expect(bigger?.amountML == 300)
        #expect(try store.activeWaterDraft(now: now.addingTimeInterval(10))?.amountML == 300)

        #expect(try WaterDraftAction.apply(.cancel, store: store, now: now.addingTimeInterval(10), reload: false) == nil)
        #expect(try store.waterDraft() == nil)
        #expect(try store.waterLog().entries.isEmpty)
    }

    @Test func staleDraftsReadAsIdle() throws {
        try store.updateWaterDraft { $0 = WaterDraft(amountML: 250, startedAt: now) }
        #expect(try store.activeWaterDraft(now: now.addingTimeInterval(121)) == nil)
    }

    @Test func startUsesTheStoredSettingsAmount() throws {
        try store.updateSettings { $0.widgetAmountML = 450 }
        #expect(try WaterDraftAction.apply(.start, store: store, now: now, reload: false)?.amountML == 450)
    }

    @Test func commitTakesTheDraftAndClearsIt() throws {
        try store.updateWaterDraft { $0 = WaterDraft(amountML: 400, startedAt: now) }
        #expect(try WaterDraftAction.takeCommit(store: store, now: now.addingTimeInterval(30)) == 400)
        #expect(try store.waterDraft() == nil)
        // A second ✓ (double tap) logs nothing.
        #expect(try WaterDraftAction.takeCommit(store: store, now: now.addingTimeInterval(31)) == nil)
    }

    @Test func commitOfAStaleDraftClearsItAndLogsNothing() throws {
        try store.updateWaterDraft { $0 = WaterDraft(amountML: 400, startedAt: now) }
        #expect(try WaterDraftAction.takeCommit(store: store, now: now.addingTimeInterval(500)) == nil)
        #expect(try store.waterDraft() == nil)
    }
}
