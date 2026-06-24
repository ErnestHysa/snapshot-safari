#!/usr/bin/env bash
# Scripts/release/build-release.sh
#
# Full release pipeline run from a clean tree. Executes the unit tests,
# then calls build-app.sh to assemble the .app, then stages it in
# Release/staging/ so make-dmg.sh and downstream tools can find it.
#
# Does NOT require Apple credentials — works for unsigned local builds too.
# For signed releases, follow up with sign-app.sh, notarize-dmg.sh, and
# staple-and-verify.sh.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR"

# Ensure scripts are executable (idempotent — safe to always run).
find Scripts -name "*.sh" -exec chmod +x {} \;

echo "==> swift test (release gate)"
swift test

echo "==> ./Scripts/build-app.sh release"
./Scripts/build-app.sh release

APP_NAME="SnapshotSafari"
APP_BUNDLE=".build/${APP_NAME}.app"
STAGING_DIR="Release/staging"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: ${APP_BUNDLE} not found after build-app.sh" >&2
    exit 1
fi

mkdir -p "${STAGING_DIR}"
rm -rf "${STAGING_DIR:?}/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"

# Pull version info from the staged bundle's embedded Info.plist.
PLIST="${STAGING_DIR}/${APP_NAME}.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || echo "1.0.0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || echo "1")"

echo
echo "Release staged at: ${STAGING_DIR}/${APP_NAME}.app"
echo "  Version: ${VERSION} (build ${BUILD})"
echo
echo "Next steps (unsigned local QA):"
echo "  open ${STAGING_DIR}/${APP_NAME}.app"
echo
echo "Next steps (signed public release):"
echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAMID)\""
echo "  ./Scripts/release/sign-app.sh"
echo "  ./Scripts/release/make-dmg.sh"
echo "  export NOTARY_PROFILE=\"my-profile\""
echo "  ./Scripts/release/notarize-dmg.sh Release/SnapshotSafari-${VERSION}-${BUILD}.dmg"
echo "  ./Scripts/release/staple-and-verify.sh Release/SnapshotSafari-${VERSION}-${BUILD}.dmg"