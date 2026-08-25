#!/bin/bash
# Regenerates the marketing screenshots in docs/ from the real app.
#
# For each appearance (light/dark) it opens a fullscreen gradient backdrop
# (which also covers the menu bar, so the notch island sits alone on it),
# injects a demo state into UserDefaults, launches the built app — pinned
# open with DG_SHOT_STATE where a scene needs it — and region-captures the
# island at Retina scale (2x). Requires a Retina display and screen-recording
# permission for the terminal. Best run on the built-in (notched) display.
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
swiftc -O Scripts/NotchBounds.swift -o .build/notchbounds
swiftc -O Scripts/ParkCursor.swift -o .build/parkcursor

cleanup() { pkill -x DailyGoal 2>/dev/null || true; pkill -x backdrop 2>/dev/null || true; }
trap cleanup EXIT

# A believable week for the expanded card's dots: ●●○●●● + today.
seed_history() {
  python3 - "$D" <<'EOF'
import datetime, json, subprocess, sys
d = sys.argv[1]
days = [(datetime.datetime.now() - datetime.timedelta(hours=4) - datetime.timedelta(days=k)).strftime("%Y-%m-%d")
        for k in range(6, 0, -1)]
done = [True, True, False, True, True, True]
records = [{"day": day, "goal": "…", "completed": ok} for day, ok in zip(days, done)]
payload = json.dumps(records).encode().hex()
subprocess.run(["defaults", "write", d, "history", "-data", payload], check=True)
EOF
}

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
  defaults write $D reminderInterval -float "${5:-3600}"
  defaults write $D reminderAwaySeconds -int 100000 # never "away" during shots
}

# launch_app <light|dark> [shot-state]
launch_app() {
  DG_APPEARANCE="$1" DG_SHOT_STATE="${2:-}" "$BIN" >/dev/null 2>&1 &
  sleep 2.5
}

# Capture regions, derived from the island window (640x320, top-centered on
# the notch). Collapsed shots take a wide strip across the whole notch area;
# expanded shots frame the open card.
WX=0
refresh_bounds() { read -r WX _ _ _ < <(.build/notchbounds); }
collapsed_region() { echo "$WX,0,640,56"; }
expanded_region() { echo "$((WX + 92)),0,456,160"; }

# The empty island's invite text breathes (period ~4.2 s); capture at the next
# opacity peak so the text is readable.
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
  .build/parkcursor

  set_state "" 0 0 ""
  launch_app "$MODE"
  refresh_bounds
  sleep_to_breath_peak
  screencapture -x -R"$(collapsed_region)" "docs/shot-empty$SUF.png"

  set_state "Ship the demo build" 0 3 "$YESTERDAY"
  launch_app "$MODE"
  refresh_bounds
  screencapture -x -R"$(collapsed_region)" "docs/shot-active$SUF.png"

  set_state "Ship the demo build" 1 4 "$TODAY"
  launch_app "$MODE"
  refresh_bounds
  screencapture -x -R"$(collapsed_region)" "docs/shot-done$SUF.png"

  # The open island: full goal, streak, week dots, hours left.
  set_state "Ship the demo build" 0 3 "$YESTERDAY"
  seed_history
  launch_app "$MODE" expanded
  refresh_bounds
  screencapture -x -R"$(expanded_region)" "docs/shot-expanded$SUF.png"

  set_state "Ship the demo build" 0 3 "$YESTERDAY"
  seed_history
  launch_app "$MODE" editing
  refresh_bounds
  screencapture -x -R"$(expanded_region)" "docs/shot-editing$SUF.png"

  # Reminder nudge: 6 s interval, then a frame burst through the violet glow.
  set_state "Ship the demo build" 0 3 "$YESTERDAY" 6
  seed_history
  T0=$(python3 -c 'import time; print(time.time())')
  DG_APPEARANCE="$MODE" "$BIN" >/dev/null 2>&1 &
  sleep 2.5
  refresh_bounds
  REGION="$(expanded_region)"
  python3 - "$T0" "$MODE" "$REGION" "$SCRATCH" <<'EOF'
import subprocess, sys, time
t0, mode, region, scratch = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
for k in range(6):
    delay = t0 + 6.4 + 0.3 * k - time.time()
    if delay > 0:
        time.sleep(delay)
    subprocess.run(["screencapture", "-x", "-R" + region, f"{scratch}/nudge-{mode}-{k}.png"])
EOF
  cp "$SCRATCH/nudge-$MODE-2.png" "docs/shot-nudge$SUF.png"

  # Social card (dark only): the open island wearing the tagline, 1200x630 @2x.
  if [ "$MODE" = dark ]; then
    set_state "One goal. Always in sight." 0 7 "$YESTERDAY"
    seed_history
    launch_app dark expanded
    refresh_bounds
    screencapture -x -R"$((WX + 20)),0,600,315" docs/og.png
  fi

  pkill -x DailyGoal 2>/dev/null || true
  pkill -x backdrop 2>/dev/null || true
done

echo "✓ Shots written to docs/ (nudge bursts in $SCRATCH)"
