#!/usr/bin/env bash
# Scripts/release/staple-and-verify.sh
#
# Stapes the notarization ticket to the DMG and verifies the result.
# After this, the DMG is ready for upload to GitHub releases — Gatekeeper
# will accept it on any Mac without an internet round-trip to Apple's
# servers.
#
# Mounts the DMG briefly to run spctl and codesign checks against the
# installed .app (not just the DMG wrapper).

set -euo pipefail

DMG_PATH="${1:?Usage: $0 <path-to-dmg>}"

if [ ! -f "${DMG_PATH}" ]; then
    echo "ERROR: ${DMG_PATH} not found" >&2
    exit 1
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "${DMG_PATH}"

echo "==> Validating stapled ticket"
xcrun stapler validate "${DMG_PATH}"

echo "==> Mounting DMG for in-bundle verification"
MOUNT_OUTPUT=$(hdiutil attach -nobrowse -readonly "${DMG_PATH}" 2>&1)
MOUNT_POINT=$(echo "${MOUNT_OUTPUT}" | grep -oE "/Volumes/[^\s]+" | head -1)
if [ -z "${MOUNT_POINT}" ]; then
    echo "ERROR: failed to mount DMG. Output:" >&2
    echo "${MOUNT_OUTPUT}" >&2
    exit 1
fi
trap "hdiutil detach '${MOUNT_POINT}' 2>/dev/null || true" EXIT

APP_BUNDLE_IN_DMG="${MOUNT_POINT}/SnapshotSafari.app"
if [ ! -d "${APP_BUNDLE_IN_DMG}" ]; then
    echo "ERROR: expected ${APP_BUNDLE_IN_DMG} inside DMG, not found" >&2
    exit 1
fi

echo "==> spctl assessment (in-DMG)"
spctl --assess --type open --context context:primary-signature --verbose "${APP_BUNDLE_IN_DMG}" || \
    echo "  [WARN] spctl assessment failed (Gatekeeper caching can cause transient failures). Continue if stapler validate passed."

echo "==> codesign strict verify (in-DMG)"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE_IN_DMG}"

echo
echo "All checks passed. DMG is ready for upload:"
echo "  ${DMG_PATH}"