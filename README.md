<div align="center">
  <img src="docs/icon-256.png" width="88" alt="Daily Goal icon">
  <h1>Daily Goal</h1>
  <p><strong>One goal. Always in sight.</strong></p>
  <p>A tiny native macOS pill that floats above every window with your one thing for today.</p>
  <p>
    <a href="https://github.com/jpwahle/daily-goal/releases/latest/download/DailyGoal.dmg"><b>Download for macOS</b></a>
    ·
    <a href="https://jpwahle.github.io/daily-goal/"><b>Website</b></a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
    <img src="https://img.shields.io/badge/macOS-13%2B-black" alt="macOS 13+">
    <img src="https://img.shields.io/github/v/release/jpwahle/daily-goal" alt="Latest release">
    <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange" alt="Swift">
  </p>
  <br>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/shot-active-dark.png">
    <img src="docs/shot-active.png" width="334" alt="The pill: goal, day-progress ring, 3-day streak">
  </picture>
  <br>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/shot-done-dark.png">
    <img src="docs/shot-done.png" width="334" alt="Completed: green check, strikethrough, streak at 4">
  </picture>
  <br>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/shot-nudge-dark.png">
    <img src="docs/shot-nudge.png" width="334" alt="A reminder nudge: the pill glows violet to catch your eye">
  </picture>
</div>

## Why

Todo apps hold twenty things; your attention holds one. Daily Goal keeps that
one thing floating above every window, every Space, even full-screen apps —
quiet peripheral pressure until it's done.

## Install

**Download:** grab [`DailyGoal.dmg`](https://github.com/jpwahle/daily-goal/releases/latest/download/DailyGoal.dmg),
drag the app to Applications. Releases are signed with a Developer ID
certificate and notarized by Apple, so macOS opens the app without warnings.

**Or build from source** (macOS 13+, Xcode command line tools):

```bash
git clone https://github.com/jpwahle/daily-goal.git
cd daily-goal
./build.sh --run
```

## How it works

| Function | Interaction |
|---|---|
| Set your goal | Click the pill, type, press **Return** (Esc cancels, clicking away commits) |
| Mark it done | Click the ring — spring checkmark, strikethrough, confetti, soft pop |
| Feel the day pass | The ring fills as the day elapses; turns **orange** under 3 h left, **red** under 1 h |
| Stay unobtrusive | The pill fades after ~8 s idle, brightens instantly on hover |
| Get reminded | **Remind Me** in the menu bar: every 30 min up to every 3 h (default: hourly), or Off. At the Mac, the pill hops and glows violet; away, one macOS notification waits in Notification Center |
| Keep a streak | 🔥 chip appears from 2 consecutive completed days; undo-safe |
| Move it | Drag the pill by its edge; position is remembered across launches |
| Menu bar | Icon shows state at a glance (dashed = unset, target = pending, ✓ = done); menu has edit, mark done, last-7-days dots, reminder frequency, hide/show, launch at login, check for updates, quit |
| Stay current | **Check for Updates…** asks GitHub for the latest release; a quiet daily check (on by default, one API call, toggle off with **Check Daily**) surfaces a **Download…** item in the menu when a newer version exists |

While the pill has keyboard focus: **Return** edits, **Space** toggles done,
**⌘Q** quits.

## Design decisions

- **Days flip at 4 a.m.**, not midnight — finishing at 1 a.m. still counts for
  the evening it belongs to. On rollover the goal archives and the pill
  invites you to set the next one (it reappears even if hidden).
- **Never steals focus.** The panel is non-activating: clicking or typing in
  it doesn't deactivate the app you're working in.
- **The streak only survives honest completion.** Miss a day and it's gone;
  un-checking restores the exact pre-completion state.
- **Reminders nag politely.** They skip while you're editing, stop the moment
  the goal is done, and restart their countdown whenever you touch the goal.
  Away from the keyboard for a few minutes, the nudge becomes a notification —
  which replaces the previous one instead of stacking, and respects Focus modes.
- **No accounts, no telemetry.** State lives in `UserDefaults`
  (`org.gipplab.dailygoal`), including a 90-day history; reminders are local
  notifications, generated on your Mac. The app's one and only network call
  asks GitHub for the latest version number ([UpdateChecker.swift](Sources/DailyGoal/UpdateChecker.swift),
  ~100 lines) — at most once a day, nothing sent beyond the request, and
  **Check Daily** in the menu turns it off. Updates are never auto-installed.

## Project layout

```
Sources/DailyGoal/
  main.swift              app bootstrap (accessory activation policy)
  AppDelegate.swift       panel placement, day-rollover timer, frame persistence
  FloatingPanel.swift     non-activating always-on-top NSPanel + view bridge
  GoalStore.swift         state machine: logical days, streaks, history
  GoalView.swift          the pill: check ring, confetti, idle dimming, nudge bounce
  StatusBarController.swift  menu bar icon + menu
  ReminderCenter.swift    reminder timer: pill bounce at the Mac, notification when away
Scripts/MakeIcon.swift    renders the .icns at build time
Scripts/create-dmg.sh     styled drag-to-Applications DMG
Scripts/MakeDMGBackground.swift  renders the DMG window background (arrow + hint)
Scripts/make-shots.sh     regenerates docs/ screenshots from the real app (Retina, light+dark)
docs/                     landing page (GitHub Pages)
build.sh                  dev build: compile → bundle → sign (ad-hoc)
Makefile                  release: universal build → sign → notarize → DMG
```

## Releasing

Every push to `main` triggers the [release workflow](.github/workflows/release.yml):
it bumps the version from conventional-commit prefixes, builds a universal
binary, signs it with the Developer ID certificate, notarizes and staples both
the app and the DMG, and publishes a GitHub release. Locally the same pipeline
runs with:

```bash
make release-dmg VERSION=1.0.1 \
  SIGNING_IDENTITY="Developer ID Application: Jan Philip Wahle (S5NQXKYPKT)" \
  APPLE_ID=you@example.com TEAM_ID=S5NQXKYPKT KEYCHAIN_PROFILE=AC_PASSWORD
```

## License

[MIT](LICENSE) © Jan Philip Wahle
