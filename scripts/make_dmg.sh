#!/bin/bash
set -euo pipefail
fail() { echo "Error: $*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail "Usage: $0 /path/to/Release/FusionSpatialBridge.app"
app="$1"
[[ -d "$app" && "$app" == *.app ]] || fail "App does not exist: $app"
[[ -f "$app/Contents/Info.plist" ]] || fail "Missing Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
[[ -x "$app/Contents/MacOS/$executable" ]] || fail "App executable is missing"
[[ -f "$app/Contents/Resources/FusionConnector/FusionSpatialLive.py" ]] || fail "Bundled Fusion Connector missing; build Release first"
[[ -f "$app/Contents/Resources/FusionConnector/FusionSpatialLive.manifest" ]] || fail "Connector manifest missing"
[[ -f "$app/Contents/Resources/FusionConnector/connector-info.json" ]] || fail "Connector inventory missing"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/dist"
staging="$(mktemp -d "${TMPDIR:-/tmp}/FusionSpatialDMG.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$app" "$staging/FusionSpatialBridge.app"
ln -s /Applications "$staging/Applications"
output="$root/dist/FusionSpatialBridge.dmg"
/usr/bin/hdiutil create -volname "Fusion Spatial" -srcfolder "$staging" -ov -format UDZO "$output"
/usr/bin/hdiutil verify "$output"
echo "Created: $output"
