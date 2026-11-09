# Fuely — Product & Technical Decisions

Source of truth for every decision made during the design grilling (2026-11-08).
Change a decision only with the user's approval; record the change in the Changelog at the bottom.

Fuely = "fuel daily". A personal iOS app combining water intake, sleep score and a weekly workout goal.

---

## 1. Platform & constraints

| ID | Decision |
|---|---|
| P1 | iPhone app. Data comes from Apple Watch via HealthKit. **No watchOS app** in v1. |
| P2 | **Minimum iOS 18.0.** Uses Liquid Glass (`glassEffect` etc.) on iOS 26+, with `#available` fallback to `.regularMaterial`/`.ultraThinMaterial` on iOS 18–25. Same colors and layout everywhere. |
| P3 | Built with Xcode 27.1 (SDK iOS 27.1). Target device: an iPhone running iOS 26+. |
| P4 | Signed with a **free Apple ID (Personal Team)**. Rebuild every 7 days (user accepted). Limits: 10 App IDs / 7 days, 3 apps per device. Each extension needs its own App ID, so keep targets minimal (app + 1 widget extension). |
| P5 | Capabilities: HealthKit + App Groups (both supported on a free team). No push, iCloud or Siri entitlements. |
| P6 | Language **English only**. Units: **ml / L** for water, **kg / cm** for the body. |
| P7 | Replace the existing "Untitled Project.xcodeproj" and the `MyApp/` template with a fresh Fuely project (user approved). |

## 2. Water

| ID | Decision |
|---|---|
| W1 | The user enters **weight (kg)** manually in the app (onboarding + Settings). It is not read from Health. Height is not collected (see W2). |
| W2 | Suggested goal = **weight × 35 ml, rounded to the nearest 100 ml** (e.g. 70 kg → 2500 ml). Height is **not used**: weight-based estimates already scale with body size and height adds little, so Fuely doesn't ask for it. The user can always override the goal. |
| W2a | *Clarification (Phase 1):* goal = weight kg × 35 ml, rounded to the nearest 100 ml (halves round up). Height is not used (W2). |
| W2b | *Clarification (Phase 1):* default water goal before onboarding is completed = **2400 ml**. |
| W3 | Progress is a percentage that **can exceed 100%** (like the Move ring). Workouts do **not** raise the goal automatically. |
| W4 | Storage: **write to Apple Health** (`dietaryWater`). Health is the source of truth, and water logged by other apps counts toward the total. Entries go to App Group storage first, then sync to HealthKit (HealthKit is inaccessible while the phone is locked). The widget reads the App Group cache. |
| W4a | *Clarification (Phase 1):* Health is the source of truth on refresh. A Fuely entry deleted in Health is removed locally. Fuely samples found in Health but missing locally (e.g. after reinstall) are restored. Entries with a pending sync are never touched. Locally deleted entries are tombstoned so they never come back. |
| W4b | *Clarification (Phase 1):* if a HealthKit write fails for a non-lock reason (e.g. access denied), the entry stays local and still counts toward totals; the app can show "Health access off". |
| W5 | Logging paths: (a) widget **(+) adds the widget amount (default 250 ml, W6)**; (b) app quick buttons **150 / 250 / 500 ml + custom amount**; (c) a **"Log Water (amount)" App Intent** with an amount parameter (default 250, editable) for the user's own Shortcuts. **No Control Center / Lock Screen ControlWidget** (user declined). |
| W5a | *Clarification (Phase 1, W5c / P5):* only the Log Water App Intent ships. **No App Shortcuts** and no Siri phrases. |
| W6b | **Widget (+) flow (in-widget picker):** tapping **+ ml** / (+) turns the same widget into an amount picker `✕  −  250 ml  +  ✓` (50 ml steps; presets where space allows). ✓ logs (store first, then HealthKit), ✕ cancels; nothing is logged before ✓. The app is not opened. Editing expires back to normal after ~2 min. No typed input (widgets have no text entry). Circle: tapping the amount cycles presets. Replaces instant add from W5(a). |
| W6 | The default widget amount is **250 ml** (was 300), editable in Settings. The home screen medium button is just **"+"** (no text). All pickers (home and lock screen) use **glyph-only ✕ (cancel) and ✓ (log)**, no text. |
| W6a | *Clarification (Phase 1):* widget (+) uses the widget amount from Settings. The Shortcuts "Log Water" amount parameter defaults to 250 ml (independent of the Settings amount). |
| W7 | **Undo** the last entry, and **delete any entry** from Today and History (swipe to delete). Deleting also removes the HealthKit sample. *Revised by W7a: only today's entries can be deleted.* Entries written by other apps are counted and labeled with their source, but are read-only, because HealthKit only lets the app that wrote a sample delete it. |
| W7a | **Finished days are final** (2026-11-09): at **local midnight** every earlier day becomes read-only everywhere (Week list, day detail). Past-day drink rows have **no swipe action at all**, no ⓘ button and no hint text. Today (incl. today's day detail opened from Week) keeps swipe-to-delete, Undo and the ⓘ popover. No backfill into past days. A Fuely sample deleted in Apple Health is still removed locally (W4a). Revises W7. |
| W8 | **On-track pace**: expected-by-now = goal × elapsed fraction of the **drinking window**. Default window **05:00–22:00** (suits early risers). User-adjustable in onboarding and Settings. Not 24 h, because a 24 h window marks the user "behind" every morning for hours spent asleep. The widget shows total/goal; pace drives the on-track state and reminders. |
| W8a | *Clarification (Phase 1):* the window is same-day only (cannot cross midnight); start-inclusive, end-exclusive. "On track" = total ≥ expected pace, no tolerance. An invalid window never marks the user behind. A goal of 0 counts as met. |

## 3. Sleep

| ID | Decision |
|---|---|
| S1 | Apple's Sleep Score **cannot be read** by third-party apps. Verified: `HKDataTypeAppleSleepScore` is private, authorization throws "disallowed", and reading it needs private entitlements. Do not try private APIs. |
| S2 | Fuely **calculates its own score** from `HKCategoryTypeIdentifierSleepAnalysis`, following Apple's published method: **Duration 50 pts, Bedtime consistency 30 pts, Interruptions 20 pts**. Goal: as close to Apple's number as possible. |
| S2a | *Clarification (Phase 1), constants tunable during S4 calibration:* **Duration** = 50 × min(1, asleep / 8 h). **Bedtime** = 30 pts when onset is within ±30 min of the median onset of up to 14 prior main sleeps, linear to 0 at ±150 min; full 30 with fewer than 3 nights of history. **Interruptions** = 20 − 2 per awakening − 0.2 per awake minute (floor 0); an awakening is a gap ≥ 2 min. Each component is rounded; total = sum. |
| S3 | **Zero user effort in the finished app**: no manual sleep entry and no in-app calibration. |
| S4 | **Calibration during development only**: the formula constants are tuned against Apple Health scores during development. |
| S5 | Sleep goal: score **≥ 80** by default, editable. |
| S6 | Which night counts as today's: **follow Apple's Sleep Score logic**. Default approximation: the main sleep that ended between 18:00 yesterday and 14:00 today; naps are excluded. |
| S6a | *Clarification (Phase 1, also S2):* asleep samples are merged; a gap > 60 min starts a new session. A session with < 2 h asleep is a nap (ignored). Main sleep = the longest non-nap session ending in [previous day 18:00, today 14:00). If Apple Watch staged samples (core/deep/REM) form a main sleep, only those are scored; otherwise all sources are merged. |
| S8 | **Match Apple** (2026-11-09, Phase 7): Fuely's score should equal Apple's (total and all three components). The formula was rebuilt and fitted to Apple Health scores during development (shape and constants, not only constants). Rules: sleep from **all sources counts, naps included**; **Duration** is a curve with a kink at 7 h (not linear to 8 h); **Bedtime** compares onset to the **average** and penalises late much more than early (15 min late grace, 60 min early grace), full 30 with no history; **Interruptions** depend mainly on the wake-up count, with a per-wake-up allowance of free minutes. Unit tests pin the formula at synthetic inputs, including its breakpoints. Later mismatches: compare with Apple and re-tune. Replaces S4 and S2's "as close as possible". |
| S8a | *Clarification (Phase 7):* asleep = union of asleep samples from all sources; sessions split at gaps > 2 h; **sleep day D** = sessions ending in (D−1 18:00, D 18:00] (afternoon naps count for the same day); main sleep = longest session, onset = its first asleep sample; **whole clock minutes**: each minute a session touches counts once, labelled asleep or awake by whichever covers more of it (tie → asleep); minutes with no sample are neither; asleep = asleep minutes of all sessions of the sleep day; wake-ups = runs of awake minutes inside the **main sleep only** (no minimum length; gaps without samples are never wake-ups; nap wake-ups ignored); wake-up minutes = awake minutes; bedtime average = mean onset (minutes after noon) over the previous 13 calendar days that have a **real night** (main sleep ≥ 3 h asleep; nap-only days excluded), ≥ 1 night needed, else 30. Fitted to Apple Health scores during development. A day with any asleep data (incl. iPhone-only) gets a score; "—" only with no asleep data (S7 narrowed; see S7b for nap-only days). Constants live in `SleepScoreConfig`. |
| S7 | **Nights without the Watch**: show **"—"** (no data), never 0. That day is **excluded** from the sleep goal and doesn't break streaks or history. Hint: "Wear your Watch to bed to get a sleep score." No manual entry. |
| S7b | (2026-11-09, user) A **nap-only day** (no real night: main sleep < 3 h, e.g. the Watch wasn't worn the night before) gets **no score** ("—"), treated like S7. Deliberate difference from Apple, which scores such days. Naps on a day with a real night still count. |
| S7a | *Clarification (Phase 1):* the widget shows the cached sleep score only on the day it was computed. After midnight it shows "—" until the app refreshes (the widget can't read HealthKit). |

## 4. Workouts

| ID | Decision |
|---|---|
| K1 | Source: **HealthKit workouts** (everything the Watch and Fitness app record, including manually started ones such as cycling). **All workout types** count. |
| K2 | Goal set in onboarding: **minimum minutes per day** and **days per week, 1–7**. Week = **Monday–Sunday**. |
| K3 | A day's workout minutes **add up** (30 min in the morning + 30 min at night = 60). A day counts as one workout day when the total is ≥ the minimum. At most one count per day. |
| K3a | *Clarification (Phase 1):* a workout that crosses midnight counts its whole active duration on its **start** day. |

## 5. Today screen & concept

| ID | Decision |
|---|---|
| T1 | **No separate "daily condition" score.** The app shows three goals: Workout (x/y this week), Sleep (score vs goal), Water (total/goal, % and on-track state). |
| T2 | A friendly, motivational copy line derived from the goals (e.g. "Sleep ✓ and hydrated — you're set for a sharp day."). |
| T3 | **Week view** in v1: daily water %, sleep score per night, workout days. No monthly charts. |

## 6. Widgets (user picks; like Calendar's widget gallery)

| ID | Decision |
|---|---|
| G1 | **Fuely Text**: `accessoryInline` (slot above the clock): `💧1.2L · 😴82 · 🏃2/3`. Text only, no button (iOS limitation). |
| G2 | **Fuely Line**: `accessoryRectangular` (row below the clock), laid out as a single slim line `💧 1.2/2.4L · 😴 82 · 🏃 2/3  (+)`. (+) logs the widget amount (W6). Tapping the text opens the quick-log sheet. |
| G3 | **Fuely Rings**: `accessoryRectangular`, three mini rings (water, sleep, workout) + (+). |
| G4 | **Fuely Circle**: `accessoryCircular`, configurable (AppIntent configuration): water ring with (+), sleep score, or workouts x/y. |
| G5 | **Home Screen**: one `systemSmall` and one `systemMedium` widget with rings + (+). |
| G6 | Widget buttons work only when the phone is unlocked (iOS limitation; user accepted). |
| G7 | Must render correctly in full-color, vibrant (lock screen) and accented/tinted modes (`widgetRenderingMode`, `widgetAccentedRenderingMode`). |

## 7. Reminders (local notifications)

| ID | Decision |
|---|---|
| R1 | **Water**: at most **2 per day**, only when behind pace, only inside the drinking window. Toggle in Settings. |
| R1a | *Clarification (Phase 1):* at most 2 per day, fired when intake falls behind pace. Minimum spacing **2 h** (2026-11-09; low end of common "drink every 2–3 h" guidance). |
| R1b | *Clarification (Phase 1, closed 2026-11-09):* **one "Reminders" toggle** covers water and workout reminders, default **on**. The workout reminder time row is shown only while it is on. No separate workout toggle. |
| R2 | **Workout**: only when falling behind. Each morning (default **08:00**, editable): `slack = daysLeftInWeek (incl. today) − workoutsStillNeeded`. |
| R3 | slack ≥ 2 → nothing. slack = 1 → one gentle nudge ("2 workouts to go, 3 days left this week."). slack = 0 → one gentle "today's a workout day" note. slack < 0 → one quiet note, then silent for the rest of the week. |
| R3a | *Clarification (Phase 1):* slack 1 → gentle nudge and slack 0 → note, each at most once per day at the reminder time. slack < 0 → one "behind" note, then silent for the rest of the week. Nothing fires before the reminder time. |
| R5 | **Delivery** (2026-11-09): local notifications only. Fuely recomputes and reschedules pending reminders whenever water is logged (app, widget ✓, Shortcuts intent) and on app launch/foreground; the widget extension reschedules too. Water: schedule the moment the user would fall behind pace if nothing more is logged (inside the window, ≤ 2/day, ≥ 2 h apart). Workout: the next reminder-time note from the slack rules. Plus a **best-effort `BGAppRefreshTask`** (iOS decides timing; HealthKit unreadable while locked, so it then uses the App Group store only). The app never depends on it. No HealthKit background delivery. |
| R5a | *Clarification (Phase 6):* a reminder is never planned sooner than **30 min** after a user action in Fuely (1 min from background refresh). Both water reminders are scheduled up front (2nd = 1st + 2 h) and recomputed after any log. A reminder whose fire date passed counts as sent (also when muted by Focus). A missed workout reminder time rolls to the next day; the "behind" note is delivered quietly. |
| R5b | (2026-11-09) A water reminder fires only once the user is **at least 250 ml behind** pace (no 05:01 reminder at window open). The Settings switch is labelled **"Water & workout reminders"**. |
| R4 | Never more than **1 workout reminder per day**. Nothing once today's minutes are met or the weekly goal is reached. Works for any goal from 1 to 7. Tone: encouraging, never nagging. |

## 8. Onboarding

| ID | Decision |
|---|---|
| O1 | A multi-step onboarding on first launch: Welcome → Health permission (sleep, workouts, water read/write) → Body (weight) → Water goal (suggested, editable) → Drinking window (05:00–22:00 default) → Workout goal (min minutes, days/week) → Sleep goal (80) → Notifications permission → Widget tip (how to add the lock screen widget). Everything is editable later in Settings. |

## 9. Design / brand

| ID | Decision |
|---|---|
| D1 | Brand name **Fuely**. Direction **Calm & fresh**: deep ocean blue + aqua, rounded type (SF Pro Rounded), soft Liquid Glass surfaces, water-drop app icon. |
| D2 | Follows the latest Apple HIG (iOS 26/27 Liquid Glass) but with a branded identity, not plain system styling. Supports light and dark mode, Dynamic Type and accessibility labels. |
| D3 | Dates and times everywhere (Today, Week, day detail, widgets) follow the **phone's region** format; no fixed `en_US` locale. Language stays English (P-English only). |
| D4 | **Settings uses the brand design** (ocean glass cards / branded surfaces) in light and dark, matching the other screens, instead of plain system grouped rows. |

## 10. Build & verification workflow

| ID | Decision |
|---|---|
| B1 | Use the **Xcode MCP** (`xcrun mcpbridge`) to build, test and drive the device. Xcode must be open with its MCP setting enabled. |
| B2 | The main session acts as **orchestrator only**, keeping its context thin. Work is delegated to subagents (core logic, app UI, widgets, design review, device QA). |
| B3 | Verify on the real iPhone and in the simulator: screenshots in light and dark, lock screen tinted mode, and widget (+) behavior. Judge the results against HIG and the brand. |

---

## Changelog
- 2026-11-08 — Initial decisions recorded from the grilling session.
- 2026-11-08 — Phase 1 implementation defaults accepted by the user: added clarifications W2a, W2b, W4a, W4b, W5a, W6a, W8a, S2a, S6a, S7a, K3a, R1a, R1b, R3a (no existing decision changed; R1a spacing and R1b workout toggle remain open).
- 2026-11-08 — W1, W2, W2a, O1: height dropped. The goal uses weight only, and onboarding/Settings no longer ask for height (decided by Claude at the user's request).
- 2026-11-08 — D3 (dates follow phone region) and D4 (branded Settings) added by the user after the Phase 4 simulator review.
- 2026-11-08 — W6: default widget amount 300 → 250 ml; home button label "+ ml". W5 reconfirmed: no ControlWidget (Control Center prototype did nothing on device; user rejected Controls). The widget (+) flow (ask for an amount before logging) is still open: widgets can't show a prompt (device-tested).
- 2026-11-08 — W6b added: widget (+) opens an in-widget amount picker (✕ − 250 ml + ✓) instead of logging instantly (user chose option A "for now").
- 2026-11-08 — W6: medium idle button "+ ml" → "+" only; home-widget picker confirm "✓ Log" → "Log" (text only). Lock screen unchanged (user decision after HIG typography review).
- 2026-11-08 — W6 revised: home-widget picker confirm is the ✓ glyph only (no "Log" text), consistent with the ✕ glyph and the lock screen.
- 2026-11-08 — G2 revised: Fuely Line shows three lines (💧 water / 😴 sleep / 🏃 workouts), emoji sized to the text, (+) on the right of the three lines. G5: the medium idle (+) is a fixed 44 pt circle centered under the water text column (a full-width capsule varied in width with the headline, so the user asked for one consistent button). G3: Rings must fit the slot (was clipped on the right on device).
- 2026-11-08 — G5 / W8: home widgets show only "Water" + litres (no "of goal" / pace line; removed by the user). Medium: water, litres and (+) form one centered group aligned with the rings.
- 2026-11-09 — Grilling for Phases 5–7: W7a (finished days are final at local midnight; revises W7), S8 (match Apple's Sleep Score, all sources + naps, rebuild S2a/S6a), R1a closed (2 h spacing), R1b closed (one Reminders toggle), R5 (delivery: reschedule on change + best-effort background refresh).
- 2026-11-09 — R5a: Phase 6 scheduling defaults (30 min lead after a user action, both water reminders scheduled up front, passed = sent, missed workout time → next day).
- 2026-11-09 — R5b: water reminders need a ≥ 250 ml shortfall; switch label "Water & workout reminders" (user).
- 2026-11-09 — S8a: Phase 7 measurement rules (sleep day 18:00→18:00, all sources, wake-up definition, 13-day mean onset); S7 "—" now only when there is no asleep data at all.
- 2026-11-09 — S8a revised: bedtime average skips nap-only days (main sleep < 3 h); interruptions come from the main sleep only.
- 2026-11-09 — S8a revised: per-clock-minute asleep/awake vote replaces seconds/truncation and gap-based wake-ups. Sleep scoring refined to match Apple's Sleep Score.
- 2026-11-09 — S7b: nap-only days show "—" (user), deliberately unlike Apple.
- 2026-11-09 — Debug-only sleep calibration tools removed; S4/S8/S8a reworded generically (rules unchanged).
