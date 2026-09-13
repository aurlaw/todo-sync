#!/usr/bin/env bash
# Builds a signed, Ad Hoc .ipa for device install via Xcode's Devices window or
# Apple Configurator. Signing/provisioning setup (cert, profile, device
# registration) is done by Michael in the Apple Developer portal / Xcode — this
# script only wraps the `dotnet publish` invocation once those exist.
set -euo pipefail

cd "$(dirname "$0")/.."

# Local, git-ignored file with real values — see scripts/publish.local.env.example.
ENV_FILE="scripts/publish.local.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE — copy scripts/publish.local.env.example to $ENV_FILE and fill in your values." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# If the downloaded Ad Hoc .mobileprovision is sitting at scripts/TodoSync.mobileprovision
# (git-ignored, same as $ENV_FILE), pull PROVISION_PROFILE_UUID and TEAM_ID straight out of
# it instead of requiring them to be copied into $ENV_FILE by hand.
MOBILEPROVISION_FILE="${MOBILEPROVISION_FILE:-scripts/TodoSync.mobileprovision}"
if [[ -f "$MOBILEPROVISION_FILE" ]]; then
    PROFILE_PLIST="$(mktemp)"
    trap 'rm -f "$PROFILE_PLIST"' EXIT
    security cms -D -i "$MOBILEPROVISION_FILE" > "$PROFILE_PLIST"

    : "${PROVISION_PROFILE_UUID:=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$PROFILE_PLIST")}"
    : "${TEAM_ID:=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST")}"

    # Apple's build tooling (Xcode and the dotnet iOS workload alike) looks up profiles by
    # UUID in this fixed location, not wherever the .mobileprovision file happens to live —
    # install it there if it isn't already (double-clicking the file in Finder does the same).
    PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILES_DIR"
    INSTALLED_PROFILE="$PROFILES_DIR/$PROVISION_PROFILE_UUID.mobileprovision"
    if [[ ! -f "$INSTALLED_PROFILE" ]]; then
        cp "$MOBILEPROVISION_FILE" "$INSTALLED_PROFILE"
        echo "Installed provisioning profile: $INSTALLED_PROFILE"
    fi
fi

: "${TEAM_ID:?Set TEAM_ID in $ENV_FILE (Apple Developer Program Team ID), or place the profile at $MOBILEPROVISION_FILE to auto-detect it}"
: "${CODESIGN_KEY:?Set CODESIGN_KEY in $ENV_FILE, e.g. Apple Distribution: Your Name (TEAMID), or iPhone Developer: Your Name (TEAMID)}"
: "${PROVISION_PROFILE_UUID:?Set PROVISION_PROFILE_UUID in $ENV_FILE, or place the profile at $MOBILEPROVISION_FILE to auto-detect it}"

# Release+device builds always AOT-compile (unlike simulator). LLVM AOT (the default) gives
# better codegen/perf but is noticeably slower to build - combined with MtouchLink=None
# (trimming disabled, see CLAUDE.md), a full LLVM AOT build can take 10-20+ minutes. Pass
# FAST_BUILD=1 for a quicker non-LLVM AOT build while iterating on install/signing itself;
# leave it unset for a normal build.
USE_LLVM=true
if [[ "${FAST_BUILD:-0}" == "1" ]]; then
    USE_LLVM=false
    echo "FAST_BUILD=1 - building without LLVM AOT (faster, larger/slower binary)."
fi

dotnet publish src/Todo.iOS/Todo.iOS.csproj \
    -f net10.0-ios \
    -c Release \
    -p:BuildIpa=true \
    -p:CodesignKey="$CODESIGN_KEY" \
    -p:CodesignProvision="$PROVISION_PROFILE_UUID" \
    -p:MtouchTeamID="$TEAM_ID" \
    -p:MtouchUseLlvm="$USE_LLVM"

echo
echo "Publish complete. Next steps (manual, on your Mac):"
echo "  1. Find the .ipa under src/Todo.iOS/bin/Release/net10.0-ios/ios-arm64/publish/"
echo "  2. Install via Xcode > Window > Devices and Simulators (drag the .ipa onto your device), or Apple Configurator."
echo "  3. If the device isn't registered in the Ad Hoc profile yet, add it in the Apple Developer portal and re-download the profile first."
