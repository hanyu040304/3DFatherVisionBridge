# Fusion Spatial

macOS 27+ and visionOS 27+. Fusion → original USDZ → DocumentPreviewSession.
No visionOS app, server or third-party runtime is required.

## Build and package

Select the installed Xcode 27 toolchain in Xcode Settings → Locations (or set `DEVELOPER_DIR`).
The existing project and scheme remain `FusionSpatialDemo`; the product is `FusionSpatialBridge.app`.

```bash
xcodebuild -project FusionSpatialDemo/FusionSpatialDemo.xcodeproj \
  -scheme FusionSpatialDemo -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
scripts/make_dmg.sh build/Build/Products/Release/FusionSpatialBridge.app
```

`dist/FusionSpatialBridge.dmg` contains only the app and the Applications shortcut.
An unsigned/ad-hoc DMG is a local test artifact, not a Gatekeeper-ready public release.
For distribution, configure your own bundle ID and team, sign the Release app with a
Developer ID Application certificate and Hardened Runtime, then create and notarize the DMG:

```bash
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" build/Build/Products/Release/FusionSpatialBridge.app
scripts/make_dmg.sh build/Build/Products/Release/FusionSpatialBridge.app
NOTARY_PROFILE="your-existing-keychain-profile" scripts/notarize_dmg.sh dist/FusionSpatialBridge.dmg
```

Credentials, signing identities and team IDs are not stored in this repository.
The notarization script rejects unsigned/ad-hoc apps and missing/invalid profiles.

## Installation and device test

1. Drag the app from the DMG to Applications and launch it.
2. Click **Connect Fusion 360**. No admin access or folder selection is required.
3. Save your Fusion work, quit Fusion completely, and reopen it. The connector starts automatically.
4. Confirm **Fusion 360 · Connected**, then open a Fusion design.
5. Connect Vision Pro using Mac Virtual Display. The app connects automatically when the endpoint appears;
   **Connect Vision Pro** is available for retries.
6. Click **Send Now** and verify the model appears in Vision Pro.
7. Enable **Live Preview** to test automatic updates after geometry changes. It is off by default
   to preserve the manual workflow and avoid unexpected export stalls. Changes are coalesced for 1.5 seconds.
8. Complete an Extrude operation. Verify the model updates. Camera/selection-only commands should not export.
9. Test no open design, disconnected Vision Pro, missing/corrupt connector, repair, and app relaunch.

Installation: `~/Library/Application Support/Autodesk/FusionAddins/FusionSpatialLive/`.
Exchange: `~/Library/Application Support/FusionSpatialBridge/Bridge/current.usdz`.
Original USDZ packaging is preserved. Legacy Documents model data is copied only when the new model
is absent. Pending requests are never migrated. Known legacy connectors are moved into per-user
`FusionSpatialBridge/ConnectorBackups` so two discovery paths do not load duplicate connectors.
An upgrade swaps the whole connector directory atomically; the running module is not edited in place.
The UI requires a fresh heartbeat matching the installed version and installation receipt before Connected.

## Checks

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -v
scripts/test_connector_manager.sh
bash -n scripts/*.sh
```

The manager tests use temporary homes and do not alter the real Fusion installation.
Physical Fusion auto-start, Vision Pro rendering and Gatekeeper acceptance require device testing.
The send API completing does not prove the first rendered frame has appeared on the headset.
