import Foundation
import Testing
@testable import FuelyCore

@Suite struct WeeklyRecapFlowTests {
    private typealias Context = WeeklyRecapFlow.Context

    private let free = Context(isOnboarded: true, isQuickLogOpen: false)
    private let logging = Context(isOnboarded: true, isQuickLogOpen: true)
    private let onboarding = Context(isOnboarded: false, isQuickLogOpen: false)

    private let last = sampleRecap(week: RecapWeek(mondayYear: 2026, month: 11, day: 9))
    private let older = sampleRecap(week: RecapWeek(mondayYear: 2026, month: 11, day: 2), waterDays: 3)

    @Test func nothingOfferedShowsNothing() {
        var flow = WeeklyRecapFlow()
        flow.offer(nil, in: free)
        #expect(flow == WeeklyRecapFlow())
        let marked1 = flow.didAppear()
        #expect(marked1 == nil)
    }

    @Test func popUpShowsAtOnceAndIsMarkedOnce() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: free)
        #expect(flow.presented == last)
        #expect(flow.pending == nil)
        let marked2 = flow.didAppear()
        #expect(marked2 == last)
        let marked3 = flow.didAppear()
        #expect(marked3 == nil)

        flow.close()
        #expect(flow.presented == nil)
        let opensQuickLog4 = flow.recapDidDismiss(in: free)
        #expect(!opensQuickLog4)
        #expect(flow == WeeklyRecapFlow())
    }

    @Test func offeredAgainWhileOnScreenDoesNotPresentTwice() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: free)
        _ = flow.didAppear()
        flow.offer(last, in: free)
        #expect(flow.presented == last)
        #expect(flow.pending == nil)
        flow.close()
        let opensQuickLog5 = flow.recapDidDismiss(in: free)
        #expect(!opensQuickLog5)
        #expect(flow.presented == nil)
    }

    @Test func waitsForTheQuickLogSheetToClose() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: logging)
        #expect(flow.presented == nil)
        #expect(flow.pending == last)
        let marked6 = flow.didAppear()
        #expect(marked6 == nil)

        // Still open (e.g. another refresh finished): keeps waiting.
        flow.offer(last, in: logging)
        #expect(flow.presented == nil)

        flow.quickLogDidDismiss(in: free)
        #expect(flow.presented == last)
        #expect(flow.pending == nil)
        let marked7 = flow.didAppear()
        #expect(marked7 == last)
    }

    @Test func neverShowsOverOnboarding() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: onboarding)
        #expect(flow.presented == nil)
        flow.quickLogDidDismiss(in: onboarding)
        #expect(flow.presented == nil)
        // The next open after onboarding offers it again.
        flow.offer(last, in: free)
        #expect(flow.presented == last)
    }

    @Test func aLaterCheckWithNothingToShowDropsTheWaitingRecap() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: logging)
        flow.offer(nil, in: logging)
        flow.quickLogDidDismiss(in: free)
        #expect(flow.presented == nil)
    }

    @Test func quickLogRequestOpensAtOnceWithoutARecap() {
        var flow = WeeklyRecapFlow()
        let opensNow8 = flow.requestQuickLog()
        #expect(opensNow8)
        #expect(!flow.isQuickLogWaiting)
    }

    @Test func quickLogRequestWaitsForTheRecapOnScreen() {
        var flow = WeeklyRecapFlow()
        flow.offer(last, in: free)
        let opensNow9 = flow.requestQuickLog()
        #expect(!opensNow9)
        #expect(flow.isQuickLogWaiting)
        #expect(flow.presented == last)

        flow.close()
        let opensQuickLog10 = flow.recapDidDismiss(in: free)
        #expect(opensQuickLog10)
        #expect(!flow.isQuickLogWaiting)
        #expect(flow.presented == nil)
    }

    @Test func reopenedRecapIsNotMarked() {
        var flow = WeeklyRecapFlow()
        flow.reopen(older)
        #expect(flow.presented == older)
        let marked11 = flow.didAppear()
        #expect(marked11 == nil)
        flow.close()
        let opensQuickLog12 = flow.recapDidDismiss(in: free)
        #expect(!opensQuickLog12)
        #expect(flow.presented == nil)
    }

    @Test func popUpWaitsBehindAReopenedRecap() {
        var flow = WeeklyRecapFlow()
        flow.reopen(older)
        flow.offer(last, in: free)
        #expect(flow.presented == older)
        #expect(flow.pending == last)

        // Reopening while one is on screen changes nothing.
        flow.reopen(last)
        #expect(flow.presented == older)

        flow.close()
        let opensQuickLog13 = flow.recapDidDismiss(in: free)
        #expect(!opensQuickLog13)
        #expect(flow.presented == last)
        let marked14 = flow.didAppear()
        #expect(marked14 == last)
    }

    @Test func quickLogGoesBeforeAWaitingPopUp() {
        var flow = WeeklyRecapFlow()
        flow.reopen(older)
        flow.offer(last, in: free)
        let opensNow15 = flow.requestQuickLog()
        #expect(!opensNow15)
        flow.close()
        let opensQuickLog16 = flow.recapDidDismiss(in: free)
        #expect(opensQuickLog16)
        #expect(flow.presented == nil)
        flow.quickLogDidDismiss(in: free)
        #expect(flow.presented == last)
    }

    @Test func seeingTheNewRecapThroughTheWeekButtonCounts() {
        // Offered while it is already open from the Week view.
        var flow = WeeklyRecapFlow()
        flow.reopen(last)
        let marked17 = flow.didAppear()
        #expect(marked17 == nil)
        flow.offer(last, in: free)
        #expect(flow.pending == nil)
        let marked18 = flow.didAppear()
        #expect(marked18 == last)

        // Reopened while it waits behind the quick-log sheet's closing.
        var waiting = WeeklyRecapFlow()
        waiting.offer(last, in: logging)
        waiting.reopen(last)
        #expect(waiting.pending == nil)
        let marked19 = waiting.didAppear()
        #expect(marked19 == last)
    }
}
