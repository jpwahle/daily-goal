<div align="center">
  <img src="docs/icon-256.png" width="88" alt="Daily Goal icon">
  <h1>Daily Goal</h1>
  <p><strong>One goal. Always in sight.</strong></p>
  <p>Your one thing for today, living in the Mac notch — like it was always meant to be there.</p>
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
    <img src="docs/shot-active.png" width="640" alt="The island: day-progress ring left of the camera, your goal and streak right of it">
  </picture>
  <br>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/shot-expanded-dark.png">
    <img src="docs/shot-expanded.png" width="456" alt="Hover the notch and it opens: full goal, check ring, streak, week dots, hours left">
  </picture>
  <br>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/shot-done-dark.png">
    <img src="docs/shot-done.png" width="640" alt="Completed: green check, strikethrough, streak at 4">
  </picture>
</div>

## Why

Todo apps hold twenty things; your attention holds one. Daily Goal puts that
one thing in the notch — the only part of the screen no window ever covers,
on every Space, even in full screen. The camera housing grows two black
wings: the day-progress ring on the left, your goal on the right. One
continuous shape, pixel-matched to the real notch, quiet peripheral pressure
until it's done. And it never gets in the way: closed, the island is a pure
display — your mouse acts on whatever is underneath.

No notch? The island hangs from the top edge of the screen as its own little
Dynamic Island.

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

**Or develop in Xcode:** run `xcodegen generate` (spec in `project.yml`,
`brew install xcodegen` if needed), open `DailyGoal.xcodeproj`, and hit Run —
it builds a proper ad-hoc-signed `.app` bundle, so notifications and defaults
behave like the real app.

## How it works

| Function | Interaction |
|---|---|
| Open the island | Rest the pointer on the notch (or click it) — the notch springs open into a card with the full goal, streak, last-7-days dots, and hours left. Move away and it snaps shut |
| Set your goal | Open an empty island and it's already a text field: type, press **Return** (Esc cancels, clicking away commits). Later: click the goal text, or use the menu bar |
| Mark it done | Open the island, click the ring — spring checkmark, strikethrough, confetti from the notch, soft pop |
| Feel the day pass | The ring fills as the day elapses; turns **orange** under 3 h left, **red** under 1 h. The open card counts the hours |
| Stay out of the way | Closed, the island ignores your mouse entirely — clicks land on whatever is behind it. It only becomes real when you come to the notch |
| Get reminded | **Remind Me** in the menu bar: every 30 min up to every 3 h (default: hourly), or Off. At the Mac, the notch opens and glows violet for a moment; away, one macOS notification waits in Notification Center |
| Keep a streak | 🔥 chip appears from 2 consecutive completed days; undo-safe |
| Menu bar | Icon shows state at a glance (dashed = unset, target = pending, ✓ = done); menu has edit, mark done, last-7-days dots, reminder frequency, hide/show, launch at login, check for updates, quit |
| Stay current | **Check for Updates…** asks GitHub for the latest release; a quiet automatic check (on by default; every 8 h and right after wake, one API call each, toggle off with **Check Automatically**) surfaces an **Install…** item in the menu when a newer version exists. One click downloads the release from GitHub, verifies its SHA-256 checksum and Developer ID signature, swaps the app in place, and relaunches |

While the island has keyboard focus: **Return** edits, **Space** toggles done,
**⌘Q** quits.

## Design decisions

- **The notch is the app.** The island is one continuous black shape drawn
  flush with the camera housing — same height, same corner language (concave
  ears at the top, round corners at the bottom), measured from the system
  (`safeAreaInsets`, `auxiliaryTopLeftArea/Right`) so it's pixel-exact on
  every notched Mac. On plain displays it becomes a virtual island hanging
  from the top edge.
- **Closed means closed.** The collapsed island never takes your mouse — the
  panel ignores events entirely, so clicks pass through to the menu bar and
  windows behind. A short dwell on the notch (or a click) opens it; a cursor
  merely passing by doesn't.
- **Days flip at 4 a.m.**, not midnight — finishing at 1 a.m. still counts
  for the evening it belongs to. On rollover the goal archives and the island
  opens with an invite for the next one (even if it was hidden).
- **Never steals focus.** The panel is non-activating; it only becomes key
  while you're actually typing in it, and gives focus straight back.
- **The streak only survives honest completion.** Miss a day and it's gone;
  un-checking restores the exact pre-completion state.
- **Reminders nag politely.** They skip while you're editing, stop the moment
  the goal is done, and restart their countdown whenever you touch the goal.
  Away from the keyboard for a few minutes, the nudge becomes a notification —
  which replaces the previous one instead of stacking, and respects Focus modes.
- **No accounts, no telemetry.** State lives in `UserDefaults`
  (`org.gipplab.dailygoal`), including a 90-day history; reminders are local
  notifications, generated on your Mac. The app only ever talks to GitHub:
  one API call asks for the latest version number
  ([UpdateChecker.swift](Sources/DailyGoal/UpdateChecker.swift)) — at most
  three times a day, nothing sent beyond the request, and **Check
  Automatically** in the menu turns it off. Updates never install behind your back: only when you click
  **Install**, the release downloads from GitHub and must pass two independent
  checks before it replaces the app — the SHA-256 checksum published with the
  release, and a valid Developer ID signature for this app's team and bundle ID
  ([UpdateInstaller.swift](Sources/DailyGoal/UpdateInstaller.swift)).

## Project layout

```
Sources/DailyGoal/
  main.swift              app bootstrap (accessory activation policy)
  AppDelegate.swift       wiring: island, menu bar, reminders, day rollover
  NotchPanel.swift        non-activating always-on-top panel pinned over the notch
  NotchController.swift   the island's choreography: hover open, mouse-away close
  NotchGeometry.swift     NSScreen notch measurement (+ virtual-notch fallback)
  NotchShape.swift        the notch outline: concave ears, round bottom corners
  NotchIslandView.swift   the island: wings, expanded card, editing, confetti
  GoalStore.swift         state machine: logical days, streaks, history
  StatusBarController.swift  menu bar icon + menu
  ReminderCenter.swift    reminder timer: island glow at the Mac, notification when away
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
