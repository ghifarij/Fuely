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
- Remote: `origin` = https://github.com/ghifarij/Fuely.git (**public**). Single developer, so work directly on `main`; no PRs needed. Use a short-lived branch only for risky experiments, then merge locally.
- Claude handles git: `status`, `diff`, `add`, `commit` (writes the message), `branch`, `switch`, `merge`, `fetch`, `pull`, `stash`.
- **Never `git push`**, in any form (incl. `--force`, tags, `gh` pushes). The user pushes manually. Also blocked in `.claude/settings.json`.
- No history rewrites (`reset --hard`, `rebase`, `commit --amend` on pushed commits, `filter-repo`) without the user's explicit OK.
- Commit at the end of each finished task/phase (one commit per phase unless told otherwise). Message: imperative summary line, short body on what and why.
- No attribution: no `Co-Authored-By`, no "Generated with Claude Code", no session links.
- Author is `ghifarij <54807546+ghifarij@users.noreply.github.com>` (repo-local config). Never use a personal email.
- **Before every commit**, check the staged diff for personal data (health values, screenshots, weight, schedule, location/time zone, device name/UDID, team ID, email). The repo is public; see `.gitignore` for private paths (`SleepScore/`, `Config/Signing.local.xcconfig`).
