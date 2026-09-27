#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/FusionConnector"
mkdir -p "$output"
for name in FusionSpatialLive.py FusionSpatialLive.manifest; do
    /bin/cp "$root/FusionAddin/$name" "$output/$name"
done
py_hash=$(/usr/bin/shasum -a 256 "$output/FusionSpatialLive.py" | /usr/bin/cut -d ' ' -f 1)
manifest_hash=$(/usr/bin/shasum -a 256 "$output/FusionSpatialLive.manifest" | /usr/bin/cut -d ' ' -f 1)
cat > "$output/connector-info.json" <<JSON
{"files":{"FusionSpatialLive.py":"$py_hash","FusionSpatialLive.manifest":"$manifest_hash"}}
JSON

blender_output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/BlenderConnector"
mkdir -p "$blender_output"
/bin/cp "$root/BlenderAddon/fusion_spatial_connector/__init__.py" "$blender_output/__init__.py"
