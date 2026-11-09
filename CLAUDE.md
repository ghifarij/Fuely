# Fuely

Personal iOS health app: water intake + sleep score + weekly workout goal, with lock screen and home screen widgets.

## Read first
- `docs/DECISIONS.md`: every product and technical decision. This is the source of truth. Do not deviate without the user's approval; log any change in its Changelog.
- `Progress.md`: current status and next steps. Update it when a task starts or finishes.

## Hard constraints
- iOS **18.0+** deployment target, built with Xcode 27.1. Liquid Glass APIs must sit behind `if #available(iOS 26, *)` with material fallbacks.
- **Free Apple ID (Personal Team)**: only HealthKit + App Groups. No push, iCloud or Siri. Keep targets to the app + 1 widget extension.
- **No private APIs.** Apple's Sleep Score is not readable. Fuely computes its own score (DECISIONS §3).
- HealthKit is inaccessible while locked. Write water to App Group storage first, then sync to HealthKit.
- English only; ml/L, kg/cm.

## Project layout (planned)
- `Fuely/`: SwiftUI app target
- `FuelyWidgets/`: WidgetKit extension (lock screen + home screen widgets)
- `FuelyCore/`: shared code (local Swift package or shared group): models, goal math, sleep scoring, HealthKit + App Group store, App Intents
- `FuelyTests/`: unit tests for the core math (sleep score, water pace, workout slack, reminders)

## Working style
- The main session is an **orchestrator**: it delegates implementation, review and device QA to subagents and keeps its own context thin.
- Pure logic (sleep score, pace, workout-day aggregation, reminder slack) lives in `FuelyCore` and gets unit tests, written test-first where practical.
- Build, test and run through the **Xcode MCP** (`xcrun mcpbridge`; Xcode must be open with MCP enabled). Fallback: `xcodebuild` / `xcrun devicectl` / `xcrun simctl`.
- Verify UI with screenshots (light, dark, lock screen tinted) and judge them against the Apple HIG and the Fuely brand (DECISIONS §9).

## Git
- Not a git repo yet. Initialize before the first code commit if the user agrees.
