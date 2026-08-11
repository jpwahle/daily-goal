#!/bin/bash
# Regenerates the marketing screenshots in docs/ from the real app.
#
# For each appearance (light/dark) it opens a fullscreen gradient backdrop,
# injects a demo state into UserDefaults, launches the built app with
# DG_APPEARANCE pinned, and region-captures the pill at Retina scale (2x).
# Requires a Retina display and screen-recording permission for the terminal.
#
# NOTE: overwrites the current UserDefaults state of org.gipplab.dailygoal —
# export it first if you care about it:
#   defaults export org.gipplab.dailygoal /tmp/dg-backup.plist
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="$(xcrun --show-sdk-path)"

BIN="dist/Daily Goal.app/Contents/MacOS/DailyGoal"
[ -x "$BIN" ] || { echo "build first: ./build.sh" >&2; exit 1; }

D=org.gipplab.dailygoal
TODAY=$(date -v-4H +%Y-%m-%d)
YESTERDAY=$(date -v-4H -v-1d +%Y-%m-%d)
SCRATCH=".build/shots"
mkdir -p "$SCRATCH"

echo "▸ Compiling helpers…"
swiftc -O Scripts/ShotBackdrop.swift -o .build/backdrop
swiftc -O Scripts/PillBounds.swift -o .build/pillbounds

cleanup() { pkill -x DailyGoal 2>/dev/null || true; pkill -x backdrop 2>/dev/null || true; }
trap cleanup EXIT

# set_state <goal> <completed 0|1> <streak> <lastCompletedDay|""> [reminderIntervalSeconds]
set_state() {
  pkill -x DailyGoal 2>/dev/null || true
  sleep 0.4
  if [ -n "$1" ]; then defaults write $D goal -string "$1"
  else defaults delete $D goal 2>/dev/null || true; fi
  defaults write $D completed -int "$2"
  defaults write $D streak -int "$3"
  if [ -n "${4:-}" ]; then defaults write $D lastCompletedDay -string "$4"
  else defaults delete $D lastCompletedDay 2>/dev/null || true; fi
  defaults write $D dayKey -string "$TODAY"
  defaults delete $D history 2>/dev/null || true
  # Park the pill mid-screen, away from the menu bar, for clean captures.
  defaults write $D panelX -int 560
  defaults write $D panelY -int 430
  defaults write $D reminderInterval -float "${5:-3600}"
  defaults write $D reminderAwaySeconds -int 100000 # never "away" during shots
}

launch_app() { # <light|dark>
  DG_APPEARANCE="$1" "$BIN" >/dev/null 2>&1 &
  sleep 2.5
}

# pill_region <hpad> <vpad> — capture rect around the pill, in points
pill_region() {
  local PX PY PW PH
  read -r PX PY PW PH < <(.build/pillbounds)
  echo "$((PX + 30 - $1)),$((PY + 30 - $2)),$((PW - 60 + 2 * $1)),$((PH - 60 + 2 * $2))"
}

# The empty pill's invite text breathes (opacity ~0.38…0.94, period ~4.2 s);
# capture at the next opacity peak so the text is readable.
sleep_to_breath_peak() {
  python3 - <<'EOF'
import math, time
t = time.time() - 978307200.0          # seconds since NSDate reference
period = 2 * math.pi / 1.5
peak = (math.pi / 2) / 1.5
k = math.ceil((t + 1.0 - peak) / period)
time.sleep(max(0, peak + k * period - t))
EOF
}

for MODE in light dark; do
  SUF=""; [ "$MODE" = dark ] && SUF="-dark"
  echo "▸ $MODE shots…"
  pkill -x backdrop 2>/dev/null || true
  .build/backdrop "$MODE" &
  sleep 1.2

  set_state "" 0 0 ""
  launch_app "$MODE"
  sleep_to_breath_peak
  screencapture -x -R"$(pill_region 46 38)" "docs/shot-empty$SUF.png"

  set_state "Ship the demo build" 0 3 "$YESTERDAY"
  launch_app "$MODE"
  screencapture -x -R"$(pill_region 46 38)" "docs/shot-active$SUF.png"

  set_state "Ship the demo build" 1 4 "$TODAY"
  launch_app "$MODE"
  screencapture -x -R"$(pill_region 46 38)" "docs/shot-done$SUF.png"

  # Reminder nudge: 6 s interval, then a frame burst through hop + glow.
  set_state "Ship the demo build" 0 3 "$YESTERDAY" 6
  T0=$(python3 -c 'import time; print(time.time())')
  DG_APPEARANCE="$MODE" "$BIN" >/dev/null 2>&1 &
  sleep 2.5
  REGION="$(pill_region 46 38)"
  python3 - "$T0" "$MODE" "$REGION" "$SCRATCH" <<'EOF'
import subprocess, sys, time
t0, mode, region, scratch = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
for k in range(6):
    delay = t0 + 6.2 + 0.3 * k - time.time()
    if delay > 0:
        time.sleep(delay)
    subprocess.run(["screencapture", "-x", "-R" + region, f"{scratch}/nudge-{mode}-{k}.png"])
EOF

  # Social card (dark only): the pill wearing the tagline, 1200x630 @2x.
  if [ "$MODE" = dark ]; then
    set_state "One goal. Always in sight." 0 7 "$YESTERDAY"
    launch_app dark
    read -r PX PY PW PH < <(.build/pillbounds)
    CX=$((PX + PW / 2)); CY=$((PY + PH / 2))
    screencapture -x -R"$((CX - 300)),$((CY - 145)),600,315" docs/og.png
  fi

  pkill -x DailyGoal 2>/dev/null || true
  pkill -x backdrop 2>/dev/null || true
done

echo "✓ Shots written to docs/ (nudge bursts in $SCRATCH)"
