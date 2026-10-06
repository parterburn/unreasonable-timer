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
AX_FIND_TOOL="${RUNNER_TEMP:-/tmp}/ax-find"
swiftc -O scripts/ax-find.swift -o "$AX_FIND_TOOL"

# Behaviour checks, written to checks.txt beside the images; the workflow fails after
# committing them if any failed.
CHECKS="$OUT/checks.txt"
: >"$CHECKS"
check() { # <description> <command...>
  if "${@:2}"; then echo "PASS  $1" | tee -a "$CHECKS"; else echo "FAIL  $1" | tee -a "$CHECKS"; fi
}
front_app() { lsappinfo info -only name "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }

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

capture_screen() { # <name>: the whole screen, for menus that are their own windows
  screencapture -x "$OUT/$1.png"
  sips -s format jpeg -s formatOptions 82 "$OUT/$1.png" --out "$OUT/$1.jpg" >/dev/null
  rm "$OUT/$1.png"
  echo "captured $1"
}

open "untimer://open?time=20&lead=$LEAD&people=12"
sleep 3
capture countdown-1-paused

# Right-click: the countdown's menu, each item with its key. Esc closes the menu.
read -r WX WY WW WH <<<"$("$WINDOW_ID_TOOL" "$NAME" --bounds)"
"$CLICK_TOOL" right $((WX + WW / 2)) $((WY + WH / 3))
sleep 1;  capture_screen countdown-1b-right-click-menu
"$HOLD_KEY_TOOL" escape 0
sleep 1

open "untimer://start?time=20&lead=$LEAD&people=12"
sleep 3;  capture countdown-2-running    # ~17 left
# Esc while counting only asks; the timer keeps going.
"$HOLD_KEY_TOOL" escape 0
sleep 0.6; capture countdown-2b-esc-asks-before-editing
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
launch -UTAppearance dark
capture setup-3-dark

# The preview at each moment, with text long enough to wrap and a room size.
LONG="lead=What%20is%20your%20favorite%20thing%20to%20do%20here%3F%20What%20is%20your%20favorite%20thing%20to%20do%20here%3F&people=12"
open "untimer://edit?time=600&$LONG"
sleep 3;  capture setup-4-preview-start-wrapping
launch -UTAppearance dark -UTPreviewMoment warning
open "untimer://edit?time=600&$LONG"
sleep 3;  capture setup-5-preview-15-seconds-left
launch -UTAppearance dark -UTPreviewMoment end
open "untimer://edit?time=600&$LONG"
sleep 3;  capture setup-6-preview-time-is-up
# No text at zero (an empty done=): time's up shows only the overtime count.
open "untimer://edit?time=600&done=&people=12"
sleep 3;  capture setup-6b-preview-no-text-at-zero

# Each text's own size, in the preview and on the countdown. At 200% the stage shrinks back to
# fit the window rather than pushing text off it.
SIZES="timersize=140&leadsize=70&textsize=130&donesize=150&peoplesize=120"
launch
open "untimer://edit?time=600&$LONG&$SIZES"
sleep 3;  capture setup-8-sizes
open "untimer://open?time=20&lead=$LEAD&people=12&$SIZES"
sleep 3;  capture countdown-9-sizes
open "untimer://open?time=20&$LONG&timersize=200&leadsize=200"
sleep 3;  capture countdown-10-sizes-200-still-fit

# ↑/↓ step the field being edited, holding to repeat: from 10:00, ↑ and four repeats in the
# seconds field make 10:05, then ↓ and two repeats in the minutes field make 7:05.
open "untimer://edit?time=600"
sleep 3
if TIME_FIELD="$("$AX_FIND_TOOL" "$NAME" AXTextField 2)"; then
  read -r FX FY <<<"$TIME_FIELD"
  "$CLICK_TOOL" "$FX" "$FY"; sleep 0.5
  "$HOLD_KEY_TOOL" up 4;     sleep 0.5
  echo "seconds field: $("$AX_FIND_TOOL" "$NAME" AXTextField 2 value)"
  check "holding ↑ in the seconds field steps :00 to :05" [ "$("$AX_FIND_TOOL" "$NAME" AXTextField 2 value)" = "05" ]
  read -r FX FY <<<"$("$AX_FIND_TOOL" "$NAME" AXTextField 1)"
  "$CLICK_TOOL" "$FX" "$FY"; sleep 0.5
  "$HOLD_KEY_TOOL" down 2;   sleep 0.5
  echo "minutes field: $("$AX_FIND_TOOL" "$NAME" AXTextField 1 value)"
  check "holding ↓ in the minutes field steps 10 to 07" [ "$("$AX_FIND_TOOL" "$NAME" AXTextField 1 value)" = "07" ]
  capture setup-7-arrow-keys-expect-7m05s
else
  check "found the minutes and seconds fields" false
fi

# A size can be typed: click the box for the text under the timer, select all and type 150;
# then ↑ while typing steps to 160.
"$AX_FIND_TOOL" "$NAME" AXTextField list || true
LEAD_SIZE="size-lead"   # the box's accessibility identifier
if SIZE_FIELD="$("$AX_FIND_TOOL" "$NAME" AXTextField "$LEAD_SIZE")"; then
  read -r SX SY <<<"$SIZE_FIELD"
  "$CLICK_TOOL" "$SX" "$SY"; sleep 0.5
  "$HOLD_KEY_TOOL" a 0 cmd
  for key in 1 5 0; do "$HOLD_KEY_TOOL" "$key" 0; sleep 0.15; done
  sleep 0.4
  check "typing 150 into a size box" [ "$("$AX_FIND_TOOL" "$NAME" AXTextField "$LEAD_SIZE" value)" = "150" ]
  "$HOLD_KEY_TOOL" up 0; sleep 0.5
  check "↑ while typing in a size box steps 150 to 160" [ "$("$AX_FIND_TOOL" "$NAME" AXTextField "$LEAD_SIZE" value)" = "160" ]
  capture setup-9-size-typed-150-then-up-160
else
  check "found the size box for the text under the timer" false
fi

# Sharing: Copy Link in the countdown's right-click menu puts a link to the Eco web timer on the
# clipboard, carrying the timer; opening that link (as macOS does when a shared link is clicked)
# brings the same timer up, paused.
open "untimer://open?time=20&lead=$LEAD&people=12&accent=6926E3"
sleep 3
read -r WX WY WW WH <<<"$("$WINDOW_ID_TOOL" "$NAME" --bounds)"
"$CLICK_TOOL" right $((WX + WW / 2)) $((WY + WH / 3))
sleep 1
"$AX_FIND_TOOL" "$NAME" AXMenuItem "Copy Link" press || "$HOLD_KEY_TOOL" escape 0
sleep 0.5
LINK="$(pbpaste)"
echo "copied link: $LINK"
check "Copy Link copies an unreasonable.eco/timer link with the timer in it" bash -c \
  '[[ "$1" == "https://unreasonable.eco/timer?time=20&"* && "$1" == *"people=12"* && "$1" == *"accent=6926E3"* && "$1" == *"lead=Intro%3A%20our%20first%20speaker"* ]]' _ "$LINK"
open "untimer://edit?time=600"
sleep 3
open -b com.unreasonablegroup.timer "$LINK"   # by bundle ID: `open -a` wants an absolute path
sleep 3
capture share-1-opened-from-copied-link
check "opening the copied link shows the countdown, not the form" bash -c "! '$AX_FIND_TOOL' '$NAME' AXTextField 1 >/dev/null 2>&1"

# Another accent (Eco Purple) with the singing bowl: both belong to the timer, so a link sets them.
ORANGE="accent=6926E3&sound=singing-bowl&chime15=1"
launch -UTAppearance dark
open "untimer://edit?time=600&$ORANGE"
sleep 3;  capture accent-setup-dark
open "untimer://start?time=20&lead=$LEAD&people=12&$ORANGE"
sleep 3;  capture accent-countdown-running
sleep 11; capture accent-countdown-final     # ~5 left
sleep 15; capture accent-countdown-overtime  # ~+11
launch
open "untimer://edit?time=600&$ORANGE"
sleep 3;  capture accent-setup-light

# Settings, in the main window's settings pane (one page), from the top to the footer.
launch -UTOpenSettings YES
capture settings-1-top
read -r WX WY WW WH <<<"$("$WINDOW_ID_TOOL" "$NAME" --bounds)"
"$CLICK_TOOL" scroll $((WX + WW * 2 / 3)) $((WY + WH / 2)) -25
sleep 1;  capture settings-2-shortcuts
"$CLICK_TOOL" scroll $((WX + WW * 2 / 3)) $((WY + WH / 2)) -80
sleep 1;  capture settings-3-bottom

# The shortcut to show the timer, set the way a person does it: click the box in Settings and
# press ⌃⌥⌘T. It should be saved, survive a relaunch, and bring the timer forward from another
# app, even after its window was closed.
defaults delete com.unreasonablegroup.timer KeyboardShortcuts_showTimer 2>/dev/null || true
launch -UTOpenSettings YES
if RECORDER="$("$AX_FIND_TOOL" "$NAME" AXSearchField)"; then
  read -r RX RY <<<"$RECORDER"
  echo "shortcut box at $RX,$RY"
  "$CLICK_TOOL" "$RX" "$RY"
  sleep 0.8; capture shortcut-1-clicked-ready-for-keys
  "$HOLD_KEY_TOOL" t 0 ctrl opt cmd
  sleep 1;   capture shortcut-2-recorded-ctrl-opt-cmd-t
else
  echo "couldn't find the shortcut box"
fi
SAVED="$(defaults read com.unreasonablegroup.timer KeyboardShortcuts_showTimer 2>/dev/null || true)"
echo "saved shortcut: $SAVED"
check "clicking the box and pressing ⌃⌥⌘T saves the shortcut" [ -n "$SAVED" ]

launch   # a fresh start reads the shortcut back
open -a Finder "$HOME"
sleep 2
echo "in front before the shortcut: $(front_app)"
"$HOLD_KEY_TOOL" t 0 ctrl opt cmd
sleep 2
echo "in front after the shortcut: $(front_app)"
capture_screen shortcut-3-pressed-in-finder
check "after a relaunch, ⌃⌥⌘T in Finder brings the timer forward" [ "$(front_app)" = "$NAME" ]

"$HOLD_KEY_TOOL" w 0 cmd   # close the window; the app stays running
sleep 1
check "⌘W closed the window" sh -c "! '$WINDOW_ID_TOOL' '$NAME' >/dev/null 2>&1"
open -a Finder "$HOME"
sleep 2
"$HOLD_KEY_TOOL" t 0 ctrl opt cmd
sleep 3
capture_screen shortcut-4-pressed-after-closing-the-window
check "with the window closed, ⌃⌥⌘T opens it again" sh -c "'$WINDOW_ID_TOOL' '$NAME' >/dev/null"
check "with the window closed, ⌃⌥⌘T brings the timer forward" [ "$(front_app)" = "$NAME" ]

osascript -e "tell application \"$NAME\" to quit" || true
ls -la "$OUT"
cat "$CHECKS"
