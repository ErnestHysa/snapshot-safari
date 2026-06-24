#!/usr/bin/env bash
# Scripts/release/verify-release.sh
#
# Independent verification of a release artifact (.app or DMG).
# Catches the common failure modes that bit us during the
# snapshot-safari v1.0.0 pre-release work:
#   - Stale Info.plist in the bundled .app (the SUFeedURL drift bug)
#   - Privileged entitlements under ad-hoc signature (the SIGKILL bug)
#   - Linker-signed instead of bundle-sealed (the verify --strict bug)
#   - Missing frameworks
#   - Generated DMG/zip/staging artifacts accidentally committed
#
# Works on both unsigned local builds and signed public releases. Strict
# checks (signature class, in-DMG verify) are gated by RELEASE_STRICT=1
# so local QA stays non-blocking.
#
# Usage: ./Scripts/release/verify-release.sh [path-to-app-or-dmg]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${PROJECT_DIR}"

TARGET="${1:-Release/staging/SnapshotSafari.app}"
APP_NAME="SnapshotSafari"
SOURCE_PLIST="Sources/${APP_NAME}/Info.plist"

if [ ! -e "${TARGET}" ]; then
    echo "ERROR: ${TARGET} not found" >&2
    echo "Usage: $0 [path-to-app-or-dmg]" >&2
    exit 1
fi

# If target is a DMG, mount it and verify the .app inside.
APP_BUNDLE="${TARGET}"
MOUNT_POINT=""
if [[ "${TARGET}" == *.dmg ]]; then
    echo "==> Mounting ${TARGET}"
    MOUNT_OUTPUT=$(hdiutil attach -nobrowse -readonly "${TARGET}" 2>&1)
    # hdiutil can truncate volume names (e.g. /Volumes/Snap instead of
    # /Volumes/SnapshotSafari). Find the actual mount point by looking for
    # the .app bundle inside any /Volumes/ entry that just appeared.
    for dir in /Volumes/*/; do
        if [ -d "${dir}${APP_NAME}.app" ]; then
            MOUNT_POINT="${dir%/}"
            break
        fi
    done
    if [ -z "${MOUNT_POINT}" ]; then
        echo "ERROR: could not find ${APP_NAME}.app inside mounted DMG" >&2
        echo "hdiutil output: ${MOUNT_OUTPUT}" >&2
        exit 1
    fi
    APP_BUNDLE="${MOUNT_POINT}/${APP_NAME}.app"
    trap "hdiutil detach '${MOUNT_POINT}' 2>/dev/null || true" EXIT
fi

echo "==> 1. Bundle structure"
for req in "Contents/Info.plist" "Contents/MacOS"; do
    if [ ! -e "${APP_BUNDLE}/${req}" ]; then
        echo "  [FAIL] Missing ${req}"
        exit 1
    fi
done
echo "  [OK]"

echo "==> 2. Codesign verifies (deep, strict)"
if ! codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" 2>&1; then
    echo "  [FAIL] codesign --verify rejected the bundle"
    exit 1
fi
echo "  [OK]"

echo "==> 3. Info.plist drift check (bundled vs source-tree)"
if [ -f "${SOURCE_PLIST}" ]; then
    DIFF=$(diff \
        <(/usr/libexec/PlistBuddy -x -c "Print" "${APP_BUNDLE}/Contents/Info.plist") \
        <(/usr/libexec/PlistBuddy -x -c "Print" "${SOURCE_PLIST}") 2>&1 || true)
    if [ -n "${DIFF}" ]; then
        echo "  [FAIL] Info.plist drift between source and bundle:"
        echo "${DIFF}" | sed 's/^/    /'
        if [ "${RELEASE_STRICT:-0}" = "1" ]; then
            exit 1
        fi
    else
        echo "  [OK]"
    fi
else
    echo "  [SKIP] no source plist to compare against"
fi

echo "==> 4. Privileged entitlement audit"
ENT="/tmp/$$.verify-release.entitlements.plist"
codesign -d --entitlements - "${APP_BUNDLE}" 2>/dev/null > "${ENT}" || true
if [ -s "${ENT}" ]; then
    PRIVILEGED=$(/usr/libexec/PlistBuddy -c "Print" "${ENT}" 2>/dev/null | grep -E "^    com\.apple\.developer\." || true)
    SIG=$(codesign -dv "${APP_BUNDLE}" 2>&1 | grep -E "^Signature=" || true)
    if [ -n "${PRIVILEGED}" ] && echo "${SIG}" | grep -Eq "Signature=ad ?hoc"; then
        echo "  [FAIL] Privileged entitlements under ad-hoc signature (will SIGKILL on launch):"
        echo "${PRIVILEGED}" | sed 's/^/    /'
        rm -f "${ENT}"
        exit 1
    fi
    rm -f "${ENT}"
    echo "  [OK]"
else
    echo "  [OK] No entitlements file (unsigned app — fine for local QA)"
fi

echo "==> 5. Bundle seal check"
SEALED=$(codesign -dvv "${APP_BUNDLE}" 2>&1 | grep "^Sealed Resources" || true)
if echo "${SEALED}" | grep -q "version=2"; then
    echo "  [OK] ${SEALED}"
else
    echo "  [FAIL] Bundle not properly sealed: ${SEALED:-Sealed Resources=none}"
    echo "         Re-run ./Scripts/build-app.sh — it includes a codesign --deep --sign - step"
    exit 1
fi

echo "==> 6. Embedded frameworks"
SPARKLE_COUNT=$(find "${APP_BUNDLE}/Contents/Frameworks" -maxdepth 1 -name "Sparkle.framework" -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "${SPARKLE_COUNT}" -ge 1 ]; then
    echo "  [OK] Sparkle.framework embedded"
else
    echo "  [FAIL] Sparkle.framework missing — auto-updates will not work"
    exit 1
fi

echo "==> 7. Git hygiene"
UNTRACKED=$(git status --short | grep -E "\.(dmg|zip)$|Release/staging/" || true)
if [ -n "${UNTRACKED}" ]; then
    echo "  [WARN] Untracked release artifacts present:"
    echo "${UNTRACKED}" | sed 's/^/    /'
    if [ "${RELEASE_STRICT:-0}" = "1" ]; then
        exit 1
    fi
else
    echo "  [OK]"
fi

echo
echo "PASS: ${TARGET}"