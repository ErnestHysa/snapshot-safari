#!/usr/bin/env bash
# Scripts/release/notarize-dmg.sh
#
# Submits a DMG to Apple's notary service and waits for completion.
# Required for the DMG to pass Gatekeeper on user Macs.
#
# Credential modes (priority order):
#   1. NOTARY_PROFILE — name of a notarytool keychain profile
#      (preferred; configure with `xcrun notarytool store-credentials ...`)
#   2. APPLE_ID, TEAM_ID, APP_SPECIFIC_PASSWORD env vars
#
# Either mode requires the app to have been signed with a Developer ID
# (NOT ad-hoc) before this step.

set -euo pipefail

DMG_PATH="${1:?Usage: $0 <path-to-dmg>}"

if [ ! -f "${DMG_PATH}" ]; then
    echo "ERROR: ${DMG_PATH} not found" >&2
    exit 1
fi

LOG_DIR="Release/notary-logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/$(basename "${DMG_PATH}" .dmg).notary.log"

NOTARIZE_ARGS=("${DMG_PATH}")

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Submitting ${DMG_PATH} with keychain profile '${NOTARY_PROFILE}'"
    NOTARIZE_ARGS+=(--keychain-profile "${NOTARY_PROFILE}")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    echo "==> Submitting ${DMG_PATH} with env-var credentials"
    NOTARIZE_ARGS+=(
        --apple-id "${APPLE_ID}"
        --team-id "${TEAM_ID}"
        --password "${APP_SPECIFIC_PASSWORD}"
    )
else
    echo "ERROR: no notary credentials configured." >&2
    echo "Set either NOTARY_PROFILE (preferred) or all three of APPLE_ID, TEAM_ID, APP_SPECIFIC_PASSWORD." >&2
    echo "Configure once: xcrun notarytool store-credentials <profile-name>" >&2
    exit 1
fi

xcrun notarytool submit --wait "${NOTARIZE_ARGS[@]}" 2>&1 | tee "${LOG_FILE}"

echo
echo "Notarization log saved to: ${LOG_FILE}"
echo "Next:"
echo "  ./Scripts/release/staple-and-verify.sh ${DMG_PATH}"