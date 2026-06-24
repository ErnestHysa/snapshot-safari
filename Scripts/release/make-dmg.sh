#!/usr/bin/env bash
# Scripts/release/make-dmg.sh
#
# Packages the staged .app into a versioned, compressed, read-only DMG
# using only built-in macOS tools (hdiutil + ditto). No third-party
# dependencies.
#
# Does NOT require Apple credentials. If the staged app is ad-hoc signed,
# prints a clear warning that the DMG will not pass Gatekeeper on other
# Macs (still valid for local QA).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="SnapshotSafari"
STAGED_APP="Release/staging/${APP_NAME}.app"

if [ ! -d "${STAGED_APP}" ]; then
    echo "ERROR: ${STAGED_APP} not found. Run ./Scripts/release/build-release.sh first." >&2
    exit 1
fi

# Pull version info from the staged bundle's embedded Info.plist.
PLIST="${STAGED_APP}/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || true)"
if [ -z "${VERSION}" ]; then
    VERSION="$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
fi
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || true)"
if [ -z "${BUILD}" ]; then
    BUILD="$(git rev-list --count HEAD 2>/dev/null || echo "1")"
fi

DMG_NAME="${APP_NAME}-${VERSION}-${BUILD}"
DMG_DIR="Release"
RW_DMG="${DMG_DIR}/${DMG_NAME}.rw.dmg"
FINAL_DMG="${DMG_DIR}/${DMG_NAME}.dmg"

mkdir -p "${DMG_DIR}"
rm -f "${RW_DMG}" "${FINAL_DMG}" "${FINAL_DMG}.sha256"

# Stage a directory layout for hdiutil: app + Applications symlink for
# drag-to-install UX.
DMG_STAGING_DIR="$(mktemp -d -t snapshot-safari-dmg)"
trap 'rm -rf "${DMG_STAGING_DIR}"' EXIT
ditto "${STAGED_APP}" "${DMG_STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

echo "==> Creating read/write DMG: ${RW_DMG}"
hdiutil create -srcfolder "${DMG_STAGING_DIR}" \
    -volname "${APP_NAME}" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "${RW_DMG}"

echo "==> Converting to compressed read-only DMG: ${FINAL_DMG}"
hdiutil convert "${RW_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${FINAL_DMG}"

rm -f "${RW_DMG}"

# Generate SHA256 checksum.
shasum -a 256 "${FINAL_DMG}" > "${FINAL_DMG}.sha256"

# Signature class warning (not fatal — local QA is fine unsigned).
SIG=$(codesign -dv "${STAGED_APP}" 2>&1 | grep "^Signature=" | head -1 || true)
if echo "${SIG}" | grep -Eq "Signature=ad ?hoc"; then
    echo
    echo "NOTE: App has ad-hoc signature. DMG will NOT pass Gatekeeper on other Macs."
    echo "      For distribution, sign with Developer ID first:"
    echo "        export DEVELOPER_ID_APPLICATION=\"Developer ID Application: ...\""
    echo "        ./Scripts/release/sign-app.sh"
    echo "      Then run make-dmg.sh again."
fi

echo
echo "DMG created: ${FINAL_DMG}"
echo "SHA256:      ${FINAL_DMG}.sha256"
echo
echo "Next steps:"
echo "  ./scripts/verify-release-launch.sh ${STAGED_APP}"
echo "  ./Scripts/release/verify-release.sh ${FINAL_DMG}"
if ! echo "${SIG}" | grep -Eq "Signature=ad ?hoc"; then
    echo "  export NOTARY_PROFILE=\"my-profile\""
    echo "  ./Scripts/release/notarize-dmg.sh ${FINAL_DMG}"
    echo "  ./Scripts/release/staple-and-verify.sh ${FINAL_DMG}"
fi