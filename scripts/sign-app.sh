#!/usr/bin/env bash
#
# Signs an app bundle and everything nested in it, inside out, for distribution outside the
# App Store. With identity "-" it signs ad hoc, which CI uses to check this procedure.
#
#   scripts/sign-app.sh "release/export/Unreasonable Timer.app" "Developer ID Application: …"
#
# This is done here, not by xcodebuild, because a signing identity passed to xcodebuild applies
# to every target in the build, including Swift package targets, and the build then fails with
# "conflicting provisioning settings".
#
# Environment:
#   HARDENED=yes|no   hardened runtime (required for notarization). Default yes, except for an
#                     ad hoc signature: library validation can't load ad hoc signed frameworks.
set -euo pipefail

APP="${1:?usage: sign-app.sh <app> <identity>}"
IDENTITY="${2:?usage: sign-app.sh <app> <identity>}"

if [ "$IDENTITY" = "-" ]; then
  HARDENED="${HARDENED:-no}"
  TIMESTAMP="--timestamp=none"
else
  HARDENED="${HARDENED:-yes}"
  TIMESTAMP="--timestamp"
fi

OPTIONS=()
if [ "$HARDENED" = "yes" ]; then
  OPTIONS+=(--options runtime)
fi

sign() {
  echo "  signing ${*: -1}"
  codesign --force --sign "$IDENTITY" "$TIMESTAMP" ${OPTIONS[@]+"${OPTIONS[@]}"} "$@"
}

[ -d "$APP/Contents" ] || { echo "Not an app bundle: $APP" >&2; exit 1; }
FRAMEWORKS="$APP/Contents/Frameworks"

# Inside out: helpers nested in a framework first, then the framework, then the app.
SPARKLE="$FRAMEWORKS/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  VERSION_DIR="$(cd "$SPARKLE/Versions/Current" && pwd -P)"
  for xpc in "$VERSION_DIR/XPCServices/Installer.xpc" "$VERSION_DIR/XPCServices/Downloader.xpc"; do
    if [ -e "$xpc" ]; then
      sign --preserve-metadata=entitlements "$xpc"
    fi
  done
  for helper in "$VERSION_DIR/Autoupdate" "$VERSION_DIR/Updater.app"; do
    if [ -e "$helper" ]; then
      sign "$helper"
    fi
  done
fi

for framework in "$FRAMEWORKS"/*.framework; do
  if [ -d "$framework" ]; then
    sign "$framework"
  fi
done

for library in "$FRAMEWORKS"/*.dylib; do
  if [ -f "$library" ]; then
    sign "$library"
  fi
done

sign "$APP"

echo "Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"

DETAILS="$(codesign --display --verbose=2 "$APP" 2>&1 || true)"
printf '%s\n' "$DETAILS" | grep -E "^(Identifier|Authority|TeamIdentifier|Timestamp|CodeDirectory)" || true

if [ "$HARDENED" = "yes" ]; then
  printf '%s\n' "$DETAILS" | grep -q "runtime" || { echo "The hardened runtime flag is missing from $APP" >&2; exit 1; }
fi
echo "Signed $APP"
