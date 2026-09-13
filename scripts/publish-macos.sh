#!/usr/bin/env bash
# Builds the macOS Todo.app bundle (via Todo.Desktop.csproj's existing
# CreateMacOSAppBundle target) and signs it with a Developer ID Application
# certificate (proper Gatekeeper trust chain, not a self-signed workaround).
# The cert itself is issued via the Apple Developer portal / Xcode, done by
# Michael once — this script only wraps build + codesign. Not notarized (out
# of scope for a personal, non-distributed app) — first launch still needs a
# one-time Gatekeeper bypass. Signs with src/Todo.Desktop/Entitlements.plist,
# required for a .NET app to even start under Hardened Runtime (--options
# runtime) - without it, CoreCLR's own libhostfxr.dylib (Microsoft-signed,
# different Team ID than ours) gets blocked by library validation and the
# app fails to launch at all with no visible error from `open`.
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="scripts/publish.local.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE — copy scripts/publish.local.env.example to $ENV_FILE and fill in your values." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${MACOS_CODESIGN_IDENTITY:?Set MACOS_CODESIGN_IDENTITY in $ENV_FILE to the Developer ID Application certs Common Name, as shown by security find-identity -v -p codesigning}"

dotnet build src/Todo.Desktop/Todo.Desktop.csproj -c Release

APP_BUNDLE="src/Todo.Desktop/bin/Release/net10.0/Todo.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Expected app bundle not found at $APP_BUNDLE — check the build output path above." >&2
    exit 1
fi

ENTITLEMENTS="src/Todo.Desktop/Entitlements.plist"
codesign --deep --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$MACOS_CODESIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --verbose "$APP_BUNDLE"

# Not notarized (out of scope for a personal, non-distributed app), so an unnotarized Developer
# ID signature alone can still get a hard Gatekeeper block on newer macOS with no GUI bypass
# (System Settings > Privacy & Security's "Open Anyway" button isn't reliably present anymore).
# A locally-built app usually has no com.apple.quarantine xattr in the first place (that's set
# by browsers/Mail/AirDrop etc. tagging a *downloaded* file, not by a local build) — this just
# guarantees it's gone, which is the actual thing Gatekeeper's block is reacting to.
xattr -cr "$APP_BUNDLE"

echo
echo "Signed and quarantine-cleared: $APP_BUNDLE"
echo "'open $APP_BUNDLE' should now launch directly with no Gatekeeper prompt."
