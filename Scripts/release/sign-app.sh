#!/usr/bin/env bash
# Scripts/release/sign-app.sh
#
# Re-signs the staged .app with a Developer ID + Hardened Runtime.
# Required for notarization and distribution outside the Mac App Store.
#
# Requires the DEVELOPER_ID_APPLICATION environment variable to be set to
# the full certificate name (e.g. "Developer ID Application: Jane Doe (ABC123XYZ)").
#
# The certificate must be installed in the login keychain. After notarization
# succeeds, the .app will pass Gatekeeper on any user's Mac.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="SnapshotSafari"
STAGED_APP="Release/staging/${APP_NAME}.app"

if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "ERROR: DEVELOPER_ID_APPLICATION is not set." >&2
    echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAMID)\"" >&2
    exit 1
fi

if [ ! -d "${STAGED_APP}" ]; then
    echo "ERROR: ${STAGED_APP} not found. Run ./Scripts/release/build-release.sh first." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "${DEVELOPER_ID_APPLICATION}"; then
    echo "ERROR: '${DEVELOPER_ID_APPLICATION}' not found in keychain." >&2
    echo "Open Keychain Access and import your Developer ID Application certificate." >&2
    exit 1
fi

echo "==> Signing ${STAGED_APP} with ${DEVELOPER_ID_APPLICATION}"
codesign --force --deep --options runtime --timestamp \
    --entitlements "Sources/${APP_NAME}/Resources/Entitlements/${APP_NAME}.entitlements" \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${STAGED_APP}"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"

echo
echo "Signed successfully. Next:"
echo "  ./Scripts/release/make-dmg.sh"