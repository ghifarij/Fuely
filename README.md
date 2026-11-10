# Fuely

**Fuel daily.** A personal iOS health app that brings three daily goals onto one screen and onto the lock screen: **water intake**, a **sleep score**, and a **weekly workout goal**.

Fuely reads sleep and workouts recorded by Apple Watch through HealthKit, logs water to Apple Health, and offers lock screen and home screen widgets that let you log a drink without opening the app.

> Platform: iPhone, iOS 18.0+ (Liquid Glass on iOS 26+) · Language: Swift / SwiftUI · Status: in daily personal use

---

## Project overview

| | |
|---|---|
| **Type** | Personal project, native iOS app + WidgetKit extension |
| **Problem** | Water, sleep and workout data lives in different apps. Apple's own Sleep Score can't be read by third-party apps, and logging water usually means unlocking the phone and opening an app. |
| **Solution** | One "Today" view with three goals, Fuely's own sleep score built to match Apple's, and interactive widgets that log water straight from the lock screen. |
| **Scale** | ~13,000 lines of Swift, 1 app target, 1 widget extension, 1 shared Swift package, 340+ unit tests |

### Features

- **Water tracking**
  - Suggested daily goal from body weight (weight × 35 ml), which you can change.
  - On-track pace measured across a configurable drinking window (default 05:00–22:00).
  - An animated water-drop card with waves, a splash when you log a drink, haptics and a once-a-day goal celebration.
  - Quick log (150 / 250 / 500 ml or a custom amount), undo, and swipe to delete.
  - Water logged by other apps in Apple Health counts toward the total.
  - A "Log Water" App Intent for your own Shortcuts.
- **Sleep score**
  - Computed on the device from HealthKit sleep analysis: duration (50 pts), bedtime consistency (30 pts) and interruptions (20 pts).
  - The formula was fitted against Apple Health's scores during development so the numbers match.
  - Nights without data show "—", never 0.
- **Workouts**
  - Weekly goal set as *minimum minutes per day* × *days per week*.
  - Every workout type recorded in HealthKit counts, and several sessions in one day add up.
- **Widgets**
  - Four lock screen widgets (Text, Line, Rings, Circle) and a small and a medium home screen widget.
  - An in-widget amount picker (`✕ − 250 ml + ✓`) logs water without opening the app.
  - Correct rendering in full-color, vibrant and tinted modes.
- **Reminders**
  - Local notifications only when you fall behind: at most 2 water reminders a day, and workout nudges based on how many days are left in the week.
- **Week view**
  - Daily water %, sleep scores and workout days for the current week and up to 12 weeks back.
  - Finished days become read-only at midnight.
- **Polish**
  - Light and dark mode, Dynamic Type up to accessibility sizes, VoiceOver labels.
  - Respects Reduce Motion and Low Power Mode.
  - Dates and times follow the phone's region format.

---

## My role and contributions

I'm the **sole developer, product owner and designer** of Fuely, built end to end for my own daily use. I used **Claude Code** as an AI coding agent: I set the product direction and every decision, and the agent wrote much of the implementation under my review.

**Product and design**
- Defined the scope and wrote every product rule in [`docs/DECISIONS.md`](docs/DECISIONS.md) (80 numbered decisions with a changelog), for example how pace is measured, which night counts as "today's" sleep, and when a reminder may fire.
- Created the brand: the "Calm & fresh" ocean/aqua palette, SF Pro Rounded type, Liquid Glass surfaces and the water-drop app icon.
- Designed the widget set and the in-widget amount picker, then revised it after testing on a device (for example, I removed the widget animations so logging feels instant).

**Engineering**
- Designed the architecture: a shared `FuelyCore` Swift package holding all pure logic, used by both the app and the widget extension.
- Built an **offline-first water store**: entries are written to App Group storage first and synced to HealthKit later, because HealthKit can't be accessed while the phone is locked. The sync queue, tombstones and reconciliation make Apple Health the source of truth.
- **Reverse-engineered a sleep score that matches Apple's.** Apple's score is private, so I rebuilt the formula (a duration curve, bedtime asymmetry, a wake-up allowance) and fitted it to Apple Health's results.
- Built the reminder planner: it schedules water and workout notifications ahead of time and reschedules them whenever something changes (app, widget or Shortcut).
- Kept the logic test-first: pace, sleep scoring, workout aggregation, reminder planning, day locking and DST/time-zone edge cases are covered by **340+ unit tests**.

**Debugging and QA**
- Diagnosed a device-only bug where widget buttons did nothing on iOS 26. iOS's App Intents indexer was rejecting intents defined in a statically linked Swift package. I moved the intent into a shared source file compiled into both targets.
- Verified every screen in light and dark mode, at accessibility text sizes, on the 4.7" iPhone SE and with the iOS 18 fallbacks, judging the results against Apple's Human Interface Guidelines. Ran the on-device checklist (widgets, HealthKit, reminders, sleep score accuracy).

---

## Technologies and tools

| Area | Used |
|---|---|
| **Language** | Swift (`FuelyCore` in Swift 6 language mode; the app targets are also clean in Swift 6 mode) |
| **UI** | SwiftUI, Liquid Glass (`glassEffect`) with material fallbacks for iOS 18–25, `TimelineView` + custom `Shape` animation, SF Symbols, SF Pro Rounded |
| **Apple frameworks** | HealthKit (sleep analysis, workouts, dietary water), WidgetKit (accessory + system families, interactive widgets, AppIntent configuration), App Intents, UserNotifications, BackgroundTasks (`BGAppRefreshTask`), Observation (`@Observable`) |
| **Data** | App Group shared container, JSON files with `NSFileCoordinator`, HealthKit as the source of truth |
| **Architecture** | Local Swift package (`FuelyCore`) for pure logic, protocol-based HealthKit and notification clients with test fakes |
| **Testing** | Swift Testing (`@Test`), parameterized tests, fake HealthKit client, fixed test calendars for DST and time zones |
| **Tooling** | Xcode 27.1, Xcode MCP (`xcrun mcpbridge`), `xcodebuild`, `xcrun simctl` / `devicectl`, Git |
| **AI-assisted development** | Claude Code (Anthropic) as a coding agent, with subagents for implementation, review and QA |

---

## Architecture

```
Fuely/            SwiftUI app: Today, Week, Quick Log, Settings, Onboarding, brand system
FuelyWidgets/     WidgetKit extension: lock screen (Text, Line, Rings, Circle) + home screen widgets, widget intents
FuelyCore/        Swift package shared by both targets
  ├─ Water/         goal + pace math
  ├─ Sleep/         sleep sessions + scoring
  ├─ Workouts/      Mon–Sun workout-day aggregation
  ├─ Reminders/     reminder policies, planner, scheduler
  ├─ HealthKit/     HealthKit client, sync queue, water log service
  ├─ Store/         App Group store, widget snapshot
  ├─ History/       week history, day editability
  ├─ Intents/       log-water + widget draft actions
  └─ Presentation/  copy, formatting and layout rules (tested)
docs/DECISIONS.md   product and technical decisions (source of truth)
Progress.md         build log by phase
```

**Data flow:** a log from the app, the widget or Shortcuts is written to the App Group store, then pushed to HealthKit when the phone is unlocked. The widget timeline reads only the App Group store, because widgets can't read HealthKit. The app refreshes from HealthKit on launch and foreground, then updates the widget snapshot and reschedules reminders.

---

## Running it yourself

Requirements: Xcode 27.1+, an iPhone running iOS 18.0+ (Apple Watch recommended for sleep and workout data).

1. Clone the repo and open `Fuely.xcodeproj`.
2. Create `Config/Signing.local.xcconfig` (gitignored) with your team:
   ```
   DEVELOPMENT_TEAM = YOURTEAMID
   ```
3. Change the bundle identifiers and App Group to your own, then build the `Fuely` scheme to your iPhone.
4. Run the unit tests with the `Fuely` scheme on an iOS simulator (⌘U). `FuelyCore` is iOS-only, so `swift test` on macOS won't build.

Fuely runs on a **free Apple ID (Personal Team)**, so it only uses HealthKit and App Groups: no push notifications, iCloud or Siri. Free provisioning profiles expire after 7 days, so the app needs a rebuild once a week.

---

## Constraints and design choices

- **No private APIs.** Apple's Sleep Score isn't readable, so Fuely computes its own.
- **Offline-first.** HealthKit can't be read or written while the phone is locked, so every log goes to the App Group store first.
- **Two targets only:** the app and one widget extension, to fit within the free-team App ID limits.
- **English only**; units are ml/L and kg.

See [`docs/DECISIONS.md`](docs/DECISIONS.md) for the full reasoning behind each choice.
