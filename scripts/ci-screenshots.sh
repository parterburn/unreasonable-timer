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
HOLD_KEY_TOOL="${RUNNER_TEMP:-/tmp}/hold-key"
swiftc -O scripts/hold-key.swift -o "$HOLD_KEY_TOOL"
CLICK_TOOL="${RUNNER_TEMP:-/tmp}/click"
swiftc -O scripts/click.swift -o "$CLICK_TOOL"

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

# The setup screen follows the system appearance (light on the runner by default).
launch
capture setup-1-light

open "untimer://open?time=20&lead=$LEAD&people=12"
sleep 3
capture countdown-1-paused

open "untimer://start?time=20&lead=$LEAD&people=12"
sleep 3;  capture countdown-2-running    # ~17 left
sleep 5;  capture countdown-3-warning    # ~11 left
sleep 6;  capture countdown-4-final      # ~5 left
sleep 32; capture countdown-5-overtime   # ~+27
# One click after zero only asks; the timer keeps counting until a second click.
read -r WX WY WW WH <<<"$("$WINDOW_ID_TOOL" "$NAME" --bounds)"
"$CLICK_TOOL" $((WX + WW / 2)) $((WY + WH / 2))
sleep 0.7; capture countdown-5b-one-click-asks-before-reset

open "untimer://start?time=2&over=0&lead=$LEAD"
sleep 5;  capture countdown-6-done

open "untimer://start?time=20&theme=light&lead=$LEAD"
sleep 3;  capture countdown-7-light

# Holding ↑ from 1:00: one press plus 20 repeats is 21 steps of 15 seconds, so 6:15.
open "untimer://open?time=60"
sleep 3;  "$HOLD_KEY_TOOL" up 20
sleep 1;  capture keys-1-held-up-expect-6m15s
# Holding ↓ from 0:50: 0:35, 0:20, 0:05, then the repeats stop short of zero.
open "untimer://open?time=50"
sleep 3;  "$HOLD_KEY_TOOL" down 10
sleep 1;  capture keys-2-held-down-expect-5s

# Digits on their own sit in the middle; the warning line only takes room from 15 seconds.
open "untimer://open?time=600"
sleep 3;  capture countdown-8-centered

# Clicking a quarter of the way along the progress bar jumps to a quarter of the time. The
# pointer stays there, so the bar shows its hover state and time label.
read -r WX WY WW WH <<<"$("$WINDOW_ID_TOOL" "$NAME" --bounds)"
echo "window: $WX $WY $WW $WH"
"$CLICK_TOOL" $((WX + WW / 4)) $((WY + WH - 6))
sleep 1;  capture seek-1-clicked-quarter-expect-2m30s

# ⌘= twice is 125%; six more reaches the largest zoom that fits; ⌘0 (View ▸ Actual Size) resets.
"$HOLD_KEY_TOOL" equals 0 cmd; sleep 0.3; "$HOLD_KEY_TOOL" equals 0 cmd
sleep 0.4; capture zoom-1-125pct
for _ in 1 2 3 4 5 6; do "$HOLD_KEY_TOOL" equals 0 cmd; sleep 0.3; done
sleep 0.2; capture zoom-2-largest
"$HOLD_KEY_TOOL" zero 0 cmd
sleep 2;  capture zoom-3-actual-size

# The timer's own theme only changes the preview at the top of the form.
open "untimer://edit?time=600&theme=light&lead=Intro:%20our%20first%20speaker"
sleep 3;  capture setup-2-light-with-light-timer

# Dark system appearance.
launch -AppleInterfaceStyle Dark
capture setup-3-dark

# Another accent (orange) with the singing bowl: both belong to the timer, so a link sets them.
ORANGE="accent=E8743B&sound=singing-bowl&chime15=1"
launch -AppleInterfaceStyle Dark
open "untimer://edit?time=600&$ORANGE"
sleep 3;  capture accent-setup-dark
open "untimer://start?time=20&lead=$LEAD&people=12&$ORANGE"
sleep 3;  capture accent-countdown-running
sleep 11; capture accent-countdown-final     # ~5 left
sleep 15; capture accent-countdown-overtime  # ~+11
launch
open "untimer://edit?time=600&$ORANGE"
sleep 3;  capture accent-setup-light

# Settings, in front of the main window. The whole screen, since the main window is larger.
capture_screen() { # <name>
  screencapture -x "$OUT/$1.png"
  sips -s format jpeg -s formatOptions 82 "$OUT/$1.png" --out "$OUT/$1.jpg" >/dev/null
  rm "$OUT/$1.png"
  echo "captured $1"
}
launch -UTOpenSettings YES
capture_screen settings
# Scrolled to the end (Sounds, Updates, the footer). Settings opens centred on the screen.
read -r _ _ SW SH <<<"$(system_profiler SPDisplaysDataType | awk '/Resolution/ { print 0, 0, $2, $4; exit }')"
"$CLICK_TOOL" scroll $(( ${SW:-1024} / 2 )) $(( ${SH:-768} / 2 )) -60
sleep 1;  capture_screen settings-bottom
launch -UTOpenSettings YES -UTSettingsTab shortcuts
"$CLICK_TOOL" scroll $(( ${SW:-1024} / 2 )) $(( ${SH:-768} / 2 )) -60
sleep 1;  capture_screen settings-shortcuts-bottom

osascript -e "tell application \"$NAME\" to quit" || true
ls -la "$OUT"
