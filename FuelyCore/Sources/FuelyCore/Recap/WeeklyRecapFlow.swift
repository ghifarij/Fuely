import Foundation

/// What is on screen around the weekly recap, and what waits (DECISIONS WR7, WR9). Pure: the app
/// feeds it events and shows `presented` as one full-screen cover.
///
/// Rules: the pop-up never shows before onboarding is finished, never over the quick-log sheet
/// (it waits until the sheet has closed) and never over another recap. A quick-log request that
/// arrives while a recap is on screen waits until the recap is closed.
public struct WeeklyRecapFlow: Sendable, Equatable {
    /// What else is on screen right now.
    public struct Context: Sendable, Equatable {
        /// Onboarding is finished (and the settings were read).
        public var isOnboarded: Bool
        /// The quick-log sheet is open or about to open.
        public var isQuickLogOpen: Bool

        public init(isOnboarded: Bool, isQuickLogOpen: Bool) {
            self.isOnboarded = isOnboarded
            self.isQuickLogOpen = isQuickLogOpen
        }
    }

    /// The recap on screen; nil = none.
    public private(set) var presented: WeeklyRecap?
    /// The new week's recap, waiting for its turn to pop up.
    public private(set) var pending: WeeklyRecap?
    /// A quick-log request waits for the recap on screen to close.
    public private(set) var isQuickLogWaiting = false
    /// The recap on screen is the pop-up and has not been recorded as shown yet.
    private var needsMarking = false

    public init() {}

    /// The result of the recap check after a Health refresh: the recap to pop up, or nil for none.
    public mutating func offer(_ recap: WeeklyRecap?, in context: Context) {
        guard let recap else {
            pending = nil
            return
        }
        if presented?.week == recap.week {
            // Already on screen (popped up, or reopened from the Week view): seeing it counts.
            needsMarking = true
            pending = nil
            return
        }
        pending = recap
        presentPending(in: context)
    }

    /// The Week view's "Weekly recap" button (WR9): shows a saved recap; never counts as the pop-up.
    public mutating func reopen(_ recap: WeeklyRecap) {
        guard presented == nil else { return }
        presented = recap
        needsMarking = pending?.week == recap.week
        if needsMarking { pending = nil }
    }

    /// The recap came on screen. Returns the recap to record as shown (WR7), once; nil otherwise.
    public mutating func didAppear() -> WeeklyRecap? {
        guard needsMarking, let presented else { return nil }
        needsMarking = false
        return presented
    }

    /// "Start this week": takes the recap off screen. Call `recapDidDismiss` once it is gone.
    public mutating func close() {
        presented = nil
        needsMarking = false
    }

    /// The recap has left the screen. True = open the quick-log sheet now (it was waiting).
    public mutating func recapDidDismiss(in context: Context) -> Bool {
        if isQuickLogWaiting {
            isQuickLogWaiting = false
            return true
        }
        presentPending(in: context)
        return false
    }

    /// A request for the quick-log sheet (deep link). True = open it now; false = it waits until
    /// the recap on screen is closed.
    public mutating func requestQuickLog() -> Bool {
        guard presented != nil else { return true }
        isQuickLogWaiting = true
        return false
    }

    /// The quick-log sheet has closed: a waiting recap may pop up now.
    public mutating func quickLogDidDismiss(in context: Context) {
        presentPending(in: context)
    }

    private mutating func presentPending(in context: Context) {
        guard let recap = pending, presented == nil, !isQuickLogWaiting,
              context.isOnboarded, !context.isQuickLogOpen else { return }
        presented = recap
        pending = nil
        needsMarking = true
    }
}
