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
#   PROVISIONING_PROFILE, TEAM_ID
#                     a Developer ID provisioning profile with Associated Domains for this app,
#                     to embed so shared https://unreasonable.eco/timer links open in the app
#                     (universal links). Without one the app is signed as before and those links
#                     open on the web. See README, "Shared links".
#   ASSOCIATED_DOMAINS  default "applinks:unreasonable.eco"
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

# The app's own entitlements, when there is a profile to back them. A profile that doesn't match
# this app and team would make macOS refuse to launch it, so check before embedding it.
APP_OPTIONS=()
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  [ -f "$PROVISIONING_PROFILE" ] || { echo "No provisioning profile at $PROVISIONING_PROFILE" >&2; exit 1; }
  [ -n "${TEAM_ID:-}" ] || { echo "TEAM_ID is needed with PROVISIONING_PROFILE" >&2; exit 1; }
  WORK="$(mktemp -d)"
  security cms -D -i "$PROVISIONING_PROFILE" > "$WORK/profile.plist"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
  PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK/profile.plist" 2>/dev/null || true)"
  [ "$PROFILE_APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] \
    || { echo "The provisioning profile is for '$PROFILE_APP_ID', not '$TEAM_ID.$BUNDLE_ID'" >&2; exit 1; }
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.associated-domains' "$WORK/profile.plist" >/dev/null 2>&1 \
    || { echo "The provisioning profile doesn't include Associated Domains; enable it for the App ID and make the profile again" >&2; exit 1; }

  cat > "$WORK/app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>$TEAM_ID.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$TEAM_ID</string>
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>${ASSOCIATED_DOMAINS:-applinks:unreasonable.eco}</string>
  </array>
</dict>
</plist>
PLIST
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  APP_OPTIONS+=(--entitlements "$WORK/app.entitlements")
  echo "  embedding the provisioning profile for $TEAM_ID.$BUNDLE_ID (${ASSOCIATED_DOMAINS:-applinks:unreasonable.eco})"
fi

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

sign ${APP_OPTIONS[@]+"${APP_OPTIONS[@]}"} "$APP"

echo "Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"

DETAILS="$(codesign --display --verbose=2 "$APP" 2>&1 || true)"
printf '%s\n' "$DETAILS" | grep -E "^(Identifier|Authority|TeamIdentifier|Timestamp|CodeDirectory)" || true

if [ "$HARDENED" = "yes" ]; then
  printf '%s\n' "$DETAILS" | grep -q "runtime" || { echo "The hardened runtime flag is missing from $APP" >&2; exit 1; }
fi
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  codesign --display --entitlements - "$APP" 2>/dev/null | grep -q "applinks:" \
    || { echo "The associated domains entitlement is missing from $APP" >&2; exit 1; }
  echo "Associated domains: ${ASSOCIATED_DOMAINS:-applinks:unreasonable.eco}"
fi
echo "Signed $APP"
