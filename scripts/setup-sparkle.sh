#!/usr/bin/env bash
#
# One-time Sparkle setup: creates the EdDSA signing key in your login Keychain (or reuses the
# one already there) and writes its public half into project.yml as SUPublicEDKey.
#
#   scripts/setup-sparkle.sh
#
# The private key stays in your Keychain and is never written to the repo. Back it up when this
# finishes: without it you can never ship an update to copies that are already installed.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED_DATA="${DERIVED_DATA:-release/DerivedData}"
fail() { printf '%s\n' "$1" >&2; exit 1; }

command -v xcodegen >/dev/null || fail "Install XcodeGen first: brew install xcodegen"

echo "==> Resolving packages (this downloads Sparkle's tools)"
xcodegen generate
xcodebuild -resolvePackageDependencies \
  -project UnreasonableTimer.xcodeproj \
  -scheme UnreasonableTimer \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet

GENERATE_KEYS="$(find "$DERIVED_DATA/SourcePackages" -type f -name generate_keys -perm -u+x 2>/dev/null | head -n 1)"
[ -n "$GENERATE_KEYS" ] || fail "Could not find Sparkle's generate_keys under $DERIVED_DATA/SourcePackages"

echo "==> Creating the signing key (or finding the existing one)"
# Creates the key pair if there isn't one yet; prints the existing public key if there is.
KEYS_OUTPUT="$("$GENERATE_KEYS")"

PUBLIC_KEY="$("$GENERATE_KEYS" -p 2>/dev/null || true)"
if [ -z "$PUBLIC_KEY" ]; then
  # Older tool versions: take it from the <string> line of the instructions it prints.
  PUBLIC_KEY="$(printf '%s\n' "$KEYS_OUTPUT" | sed -nE 's|.*<string>([^<]+)</string>.*|\1|p' | head -n 1)"
fi
PUBLIC_KEY="$(printf '%s' "$PUBLIC_KEY" | tr -d '[:space:]')"

# An Ed25519 public key is 32 bytes: 44 characters of base64 ending in "=".
if ! printf '%s' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
  fail "Did not get a valid public key from generate_keys (got: '$PUBLIC_KEY')."
fi

if ! grep -q 'SUPublicEDKey:' project.yml; then
  fail "project.yml has no SUPublicEDKey line to update."
fi
# Portable in-place edit (BSD sed on macOS and GNU sed differ on -i).
sed -E "s|(SUPublicEDKey:).*|\\1 $PUBLIC_KEY|" project.yml > project.yml.tmp && mv project.yml.tmp project.yml

echo
echo "SUPublicEDKey is now in project.yml:"
grep 'SUPublicEDKey:' project.yml
cat <<EOF

Next:
  1. Back up the private key (store the file in your password manager, then delete it):
       "$GENERATE_KEYS" -x ~/Desktop/unreasonable-timer-sparkle-key
  2. Commit project.yml. Releases built from now on can update themselves.
  3. The first scripts/release.sh run after this makes macOS ask whether generate_appcast may
     use the key in your Keychain: choose "Always Allow".
EOF
