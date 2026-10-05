#!/usr/bin/env bash
#
# Drives the built app through each timer state and captures its window, so the app can be
# compared with the web /timer page. Run by .github/workflows/screenshots.yml on a macOS runner.
#
#   scripts/ci-screenshots.sh "build/Build/Products/Debug/Unreasonable Timer.app" docs/screenshots/app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: ci-screenshots.sh <app> <output dir>}"
OUT="${2:?usage: ci-screenshots.sh <app> <output dir>}"
NAME="Unreasonable Timer"
LEAD="Intro:%20our%20first%20speaker"
mkdir -p "$OUT"
rm -f "$OUT"/*.jpg

# Recent timers, so the setup form shows its history list like the web page does.
SUPPORT="$HOME/Library/Application Support/Unreasonable Timer"
mkdir -p "$SUPPORT"
cat > "$SUPPORT/timers.json" <<'JSON'
{ "presets": [{ "id": "6B1D7E0C-5F2B-4C55-9A57-3D0F7A1E2B11", "name": "Keynote", "config": {"seconds": 1200, "warningText": "Please wrap up.", "doneText": "Time is up!", "countOver": true, "people": 300, "theme": "dark"} }],
  "recent": [
    {"seconds": 600, "warningText": "Please take your seats.", "doneText": "Time is up!", "countOver": true, "theme": "dark"},
    {"seconds": 300, "warningText": "Please take your seats.", "doneText": "Time is up!", "countOver": true, "theme": "dark"},
    {"seconds": 3600, "leadText": "Q&A", "warningText": "Wrap up", "doneText": "Time is up!", "countOver": true, "people": 40, "theme": "dark"}
  ] }
JSON

WINDOW_ID_TOOL="${RUNNER_TEMP:-/tmp}/window-id"
swiftc -O scripts/window-id.swift -o "$WINDOW_ID_TOOL"

system_profiler SPDisplaysDataType | grep -E "Resolution|UI Looks like" || true

capture() { # <name>
  local id
  id="$("$WINDOW_ID_TOOL" "$NAME")"
  screencapture -o -x -l"$id" "$OUT/$1.png"
  sips -s format jpeg -s formatOptions 82 "$OUT/$1.png" --out "$OUT/$1.jpg" >/dev/null
  rm "$OUT/$1.png"
  echo "captured $1"
}

launch() { # [extra launch arguments...]
  if pgrep -f "$NAME.app/Contents/MacOS" >/dev/null; then
    osascript -e "tell application \"$NAME\" to quit" || true
    sleep 3
  fi
  open "$APP" --args -UTWindowFrame "{{60,60},{1280,800}}" "$@"
  for _ in $(seq 1 30); do pgrep -f "$NAME.app/Contents/MacOS" >/dev/null && break; sleep 1; done
  sleep 6
}

launch
capture setup-dark

open "untimer://open?time=20&lead=$LEAD&people=12"
sleep 3
capture countdown-1-paused

open "untimer://start?time=20&lead=$LEAD&people=12"
sleep 3;  capture countdown-2-running    # ~17 left
sleep 5;  capture countdown-3-warning    # ~11 left
sleep 6;  capture countdown-4-final      # ~5 left
sleep 32; capture countdown-5-overtime   # ~+27

open "untimer://start?time=2&over=0&lead=$LEAD"
sleep 5;  capture countdown-6-done

open "untimer://start?time=20&theme=light&lead=$LEAD"
sleep 3;  capture countdown-7-light

open "untimer://edit?time=600&theme=light"
sleep 3;  capture setup-light

# Further down the form: relaunch scrolled to the controls (toggle, theme, accent, Start)
# and to the bottom (history).
# The form reopens with the last timer's theme (light, from above), so switch back to dark first.
launch -UTSetupScroll controls
open "untimer://edit?time=600"
sleep 3;  capture setup-dark-controls
open "untimer://edit?time=600&theme=light"
sleep 3;  capture setup-light-controls

launch -UTSetupScroll bottom
open "untimer://edit?time=600"
sleep 3;  capture setup-dark-bottom
open "untimer://edit?time=600&theme=light"
sleep 3;  capture setup-light-bottom

# Another accent (orange), set through the argument domain the way a saved choice would be.
launch -UTSetupScroll controls -accentColor "#E8743B"
open "untimer://edit?time=600"
sleep 3;  capture accent-setup-dark
open "untimer://start?time=20&lead=$LEAD&people=12"
sleep 3;  capture accent-countdown-running
sleep 11; capture accent-countdown-final     # ~5 left
sleep 15; capture accent-countdown-overtime  # ~+11
open "untimer://edit?time=600&theme=light"
sleep 3;  capture accent-setup-light

# Settings, in front of the main window. The whole screen, since the main window is larger.
launch -UTOpenSettings YES
screencapture -x "$OUT/settings.png"
sips -s format jpeg -s formatOptions 82 "$OUT/settings.png" --out "$OUT/settings.jpg" >/dev/null
rm "$OUT/settings.png"
echo "captured settings"

osascript -e "tell application \"$NAME\" to quit" || true
ls -la "$OUT"
