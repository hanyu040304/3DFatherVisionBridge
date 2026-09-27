#!/bin/bash
set -euo pipefail
fail() { echo "Error: $*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || fail "Usage: $0 /path/to/FusionSpatialBridge.dmg [keychain-profile]"
dmg="$1"
profile="${2:-${NOTARY_PROFILE:-}}"
[[ -f "$dmg" ]] || fail "DMG does not exist: $dmg"
[[ -n "$profile" ]] || fail "Set NOTARY_PROFILE to an existing notarytool Keychain profile"
/usr/bin/xcrun --find notarytool >/dev/null 2>&1 || fail "Xcode command-line tools with notarytool are required"
# Do not submit an unsigned or ad-hoc app as a distributable product.
mount="$(mktemp -d "${TMPDIR:-/tmp}/FusionSpatialNotary.XXXXXX")"
attached=0
cleanup() {
    if [[ "$attached" -eq 1 ]]; then /usr/bin/hdiutil detach "$mount" >/dev/null || true; fi
    rmdir "$mount" 2>/dev/null || true
}
trap cleanup EXIT
/usr/bin/hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount" >/dev/null
attached=1
app="$mount/FusionSpatialBridge.app"
[[ -d "$app" ]] || fail "FusionSpatialBridge.app is missing from DMG"
/usr/bin/codesign --verify --deep --strict "$app" || fail "App signature is invalid; sign the Release app first"
signature="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$signature" == *"Authority=Developer ID Application:"* ]] || fail "A Developer ID Application certificate is required (ad-hoc signatures are not distributable)"
[[ "$signature" == *"runtime"* ]] || fail "Enable Hardened Runtime before signing"
/usr/bin/hdiutil detach "$mount" >/dev/null
attached=0
/usr/bin/xcrun notarytool history --keychain-profile "$profile" >/dev/null || fail "Keychain profile is missing or authentication failed: $profile"
result="$(/usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json)" || fail "Notarization submission failed"
status="$(printf '%s' "$result" | /usr/bin/plutil -extract status raw -o - -)"
[[ "$status" == "Accepted" ]] || { printf '%s\n' "$result" >&2; fail "Notarization was not accepted; inspect the submission log with notarytool log"; }
/usr/bin/xcrun stapler staple "$dmg"
/usr/bin/xcrun stapler validate "$dmg"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "Notarized and verified: $dmg"
