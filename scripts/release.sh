#!/usr/bin/env bash
#
# Builds, signs, notarizes and packages Unreasonable Timer as a DMG, and updates the Sparkle
# appcast. Run on a Mac with Xcode, XcodeGen and a "Developer ID Application" certificate.
#
#   DEVELOPER_ID_APPLICATION="Developer ID Application: Unreasonable Group (ABCDE12345)" \
#   TEAM_ID=ABCDE12345 \
#   scripts/release.sh            # build everything into release/
#   PUBLISH=1 scripts/release.sh  # ...and create the GitHub release (needs `gh`)
#
# One-time setup (certificate, notarytool profile, Sparkle keys) is in README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your signing identity name}"
: "${TEAM_ID:?Set TEAM_ID to your 10-character Apple team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-unreasonable-timer}"
REPO="${REPO:-unreasonable/timer}"

APP_NAME="Unreasonable Timer"
SCHEME="UnreasonableTimer"
VERSION="$(awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
BUILD_NUMBER="$(awk '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
TAG="v${VERSION}"

OUT="release"
ARCHIVE="$OUT/$SCHEME.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/$APP_NAME.app"
DMG="$OUT/UnreasonableTimer-$VERSION.dmg"
UPDATES="$OUT/updates"   # keep old DMGs here so the appcast keeps its history

step() { printf '\n==> %s\n' "$1"; }

for tool in xcodegen xcodebuild xcrun hdiutil codesign; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

step "Releasing $APP_NAME $VERSION (build $BUILD_NUMBER)"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$OUT/dmg-staging" "$DMG"
mkdir -p "$OUT" "$UPDATES"

step "1/6 Generating the Xcode project"
xcodegen generate

step "2/6 Archiving (Release, Developer ID)"
xcodebuild archive \
  -project UnreasonableTimer.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$OUT/DerivedData" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  -quiet

step "3/6 Exporting the app"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$DEVELOPER_ID_APPLICATION</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -quiet
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() { # <file>: submit, wait, fail loudly if Apple rejects it
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

step "6/6 Updating the Sparkle appcast"
GENERATE_APPCAST="$(find "$OUT/DerivedData/SourcePackages" -type f -name generate_appcast -perm -u+x 2>/dev/null | head -n 1)"
if [ -z "$GENERATE_APPCAST" ]; then
  echo "Could not find Sparkle's generate_appcast in the build's package artifacts." >&2
  exit 1
fi
cp "$DMG" "$UPDATES/"
# Signs each archive with the EdDSA key in your login Keychain (see README, one-time setup).
"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  "$UPDATES"

echo
echo "Done."
echo "  DMG:      $DMG"
echo "  Appcast:  $UPDATES/appcast.xml"

if [ "${PUBLISH:-0}" = "1" ]; then
  step "Publishing $TAG to GitHub"
  gh release create "$TAG" "$DMG" "$UPDATES/appcast.xml" \
    --repo "$REPO" --title "$APP_NAME $VERSION" --generate-notes
else
  echo
  echo "To publish:"
  echo "  gh release create $TAG '$DMG' '$UPDATES/appcast.xml' --repo $REPO --title '$APP_NAME $VERSION' --generate-notes"
fi
