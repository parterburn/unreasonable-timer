#!/usr/bin/env bash
#
# Builds, signs, notarizes and packages Unreasonable Timer as a DMG, and updates the Sparkle
# appcast. Run on a Mac with Xcode, XcodeGen and a "Developer ID Application" certificate.
#
#   scripts/release.sh            # build everything into release/
#   PUBLISH=1 scripts/release.sh  # ...and create the GitHub release (needs `gh`)
#
# The signing identity and team ID are read from your keychain when you have exactly one
# Developer ID Application certificate; otherwise set DEVELOPER_ID_APPLICATION (and TEAM_ID).
# One-time setup (notarytool profile, Sparkle keys) is in README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-unreasonable-timer}"
REPO="${REPO:-unreasonable/timer}"

APP_NAME="Unreasonable Timer"
SCHEME="UnreasonableTimer"
VERSION="$(awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
BUILD_NUMBER="$(awk '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
SPARKLE_KEY="$(awk '/SUPublicEDKey:/ { print $2; exit }' project.yml)"
TAG="v${VERSION}"

OUT="release"
ARCHIVE="$OUT/$SCHEME.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/$APP_NAME.app"
DMG="$OUT/UnreasonableTimer-$VERSION.dmg"
UPDATES="$OUT/updates"   # keep old DMGs here so the appcast keeps its history

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '%s\n' "$1" >&2; exit 1; }

for tool in xcodegen xcodebuild xcrun hdiutil codesign security; do
  command -v "$tool" >/dev/null || fail "Missing required tool: $tool"
done

# --- Signing identity and team ----------------------------------------------------------
if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
  IDENTITIES="$(security find-identity -v -p codesigning | grep 'Developer ID Application' || true)"
  COUNT="$(printf '%s' "$IDENTITIES" | grep -c . || true)"
  if [ "$COUNT" -eq 0 ]; then
    fail "No 'Developer ID Application' certificate found in your keychain.
Create one in Xcode > Settings > Accounts > Manage Certificates."
  elif [ "$COUNT" -gt 1 ]; then
    fail "Several Developer ID identities found. Set DEVELOPER_ID_APPLICATION to one of:
$IDENTITIES"
  fi
  DEVELOPER_ID_APPLICATION="$(printf '%s' "$IDENTITIES" | sed -E 's/^[^"]*"([^"]+)".*$/\1/')"
fi
if [ -z "${TEAM_ID:-}" ]; then
  TEAM_ID="$(printf '%s' "$DEVELOPER_ID_APPLICATION" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
  [ -n "$TEAM_ID" ] || fail "Could not read the team ID from '$DEVELOPER_ID_APPLICATION'. Set TEAM_ID."
fi

step "Releasing $APP_NAME $VERSION (build $BUILD_NUMBER)"
echo "  Identity: $DEVELOPER_ID_APPLICATION"
echo "  Team:     $TEAM_ID"

# Fail now, not after a ten-minute build, if notarization isn't set up.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || fail "The notarytool profile '$NOTARY_PROFILE' doesn't work. Create it with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you@example.com> --team-id $TEAM_ID"

SPARKLE_READY=1
case "$SPARKLE_KEY" in
  REPLACE_* | "") SPARKLE_READY=0 ;;
esac
if [ "$SPARKLE_READY" -eq 0 ]; then
  echo "  Sparkle:  no SUPublicEDKey in project.yml, so the update feed will be skipped."
  echo "            Run scripts/setup-sparkle.sh to enable updates."
fi

# Sparkle only offers an update whose build number is higher than the installed one. Catch a
# forgotten bump now, not after notarization.
if [ "$SPARKLE_READY" -eq 1 ] && [ -f "$UPDATES/appcast.xml" ]; then
  LAST_BUILD="$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$UPDATES/appcast.xml" | sed -E 's/<[^>]+>//g' | sort -n | tail -n 1)"
  if [ -n "$LAST_BUILD" ] && [ "$BUILD_NUMBER" -le "$LAST_BUILD" ]; then
    fail "CURRENT_PROJECT_VERSION is $BUILD_NUMBER, but $UPDATES/appcast.xml already has build $LAST_BUILD.
Sparkle only offers updates with a higher build number, so bump CURRENT_PROJECT_VERSION in project.yml."
  fi
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR" "$OUT/dmg-staging" "$DMG"
mkdir -p "$OUT" "$UPDATES"

step "1/6 Generating the Xcode project"
xcodegen generate

step "2/6 Archiving (Release, unsigned: signing happens in the next step)"
# No signing identity here: xcodebuild would apply it to every target, including the Swift
# package targets, and fail with "conflicting provisioning settings".
xcodebuild archive \
  -project UnreasonableTimer.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

step "3/6 Signing the app (hardened runtime, inside out)"
ARCHIVED_APP="$(find "$ARCHIVE/Products" -maxdepth 3 -name '*.app' -type d | head -n 1)"
[ -n "$ARCHIVED_APP" ] || fail "No .app found in $ARCHIVE/Products"
mkdir -p "$EXPORT_DIR"
ditto "$ARCHIVED_APP" "$APP"
scripts/sign-app.sh "$APP" "$DEVELOPER_ID_APPLICATION"

notarize() { # <file>: submit, wait; notarytool exits non-zero if Apple rejects it
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

step "4/6 Notarizing and stapling the app"
ditto -c -k --keepParent "$APP" "$OUT/notarize-app.zip"
notarize "$OUT/notarize-app.zip"
xcrun stapler staple "$APP"
rm "$OUT/notarize-app.zip"

step "5/6 Building, signing, notarizing and stapling the DMG"
mkdir -p "$OUT/dmg-staging"
cp -R "$APP" "$OUT/dmg-staging/"
ln -s /Applications "$OUT/dmg-staging/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$OUT/dmg-staging" -ov -format UDZO "$DMG"
rm -rf "$OUT/dmg-staging"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

ASSETS=("$DMG")
if [ "$SPARKLE_READY" -eq 1 ]; then
  step "6/6 Updating the Sparkle appcast"
  GENERATE_APPCAST="$(find "$OUT/DerivedData/SourcePackages" -type f -name generate_appcast -perm -u+x 2>/dev/null | head -n 1)"
  [ -n "$GENERATE_APPCAST" ] || fail "Could not find Sparkle's generate_appcast in the build's package artifacts."
  cp "$DMG" "$UPDATES/"
  APPCAST_ARGS=(--download-url-prefix "https://github.com/$REPO/releases/download/$TAG/")
  # Release notes for Sparkle's update window: release-notes/<version>.md, if present.
  if [ -f "release-notes/$VERSION.md" ]; then
    cp "release-notes/$VERSION.md" "$UPDATES/$(basename "$DMG" .dmg).md"
    APPCAST_ARGS+=(--embed-release-notes)
  fi
  # Signs each archive with the EdDSA key: from SPARKLE_KEY_FILE if set (CI), otherwise from
  # your login Keychain (see README, one-time setup).
  if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
    APPCAST_ARGS+=(--ed-key-file "$SPARKLE_KEY_FILE")
  fi
  "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$UPDATES"
  ASSETS+=("$UPDATES/appcast.xml")
else
  step "6/6 Skipping the Sparkle appcast (no SUPublicEDKey yet)"
fi

echo
echo "Done."
echo "  DMG: $DMG"
[ "$SPARKLE_READY" -eq 1 ] && echo "  Appcast: $UPDATES/appcast.xml"

if [ "${PUBLISH:-0}" = "1" ]; then
  step "Publishing $TAG to GitHub"
  gh release create "$TAG" "${ASSETS[@]}" \
    --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "$APP_NAME $VERSION" --generate-notes
else
  echo
  echo "To publish:  PUBLISH=1 scripts/release.sh   (or upload the DMG to a GitHub release yourself)"
fi
