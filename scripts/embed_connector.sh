#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/FusionConnector"
mkdir -p "$output"
for name in FusionSpatialLive.py FusionSpatialLive.manifest; do
    /usr/bin/ditto "$root/FusionAddin/$name" "$output/$name"
done
py_hash=$(/usr/bin/shasum -a 256 "$output/FusionSpatialLive.py" | /usr/bin/cut -d ' ' -f 1)
manifest_hash=$(/usr/bin/shasum -a 256 "$output/FusionSpatialLive.manifest" | /usr/bin/cut -d ' ' -f 1)
cat > "$output/connector-info.json" <<JSON
{"files":{"FusionSpatialLive.py":"$py_hash","FusionSpatialLive.manifest":"$manifest_hash"}}
JSON
