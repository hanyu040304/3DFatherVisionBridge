#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ConnectorTests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
export TARGET_BUILD_DIR="$work"
export UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources
"$root/scripts/embed_connector.sh"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -sdk "$sdk" -target "$(uname -m)-apple-macos27.0" \
    "$root/FusionSpatialDemo/FusionSpatialDemo/FusionConnectorManager.swift" \
    "$root/Tests/ConnectorManagerChecks.swift" -o "$work/checks"
"$work/checks" "$work/Resources/FusionConnector"
