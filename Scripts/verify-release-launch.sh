#!/usr/bin/env bash
# scripts/verify-release-launch.sh
#
# Independent launch verification of a packaged .app bundle. Catches
# the failure mode where the .app is structurally valid but the OS
# refuses to launch it (the ad-hoc + iCloud entitlement = SIGKILL bug).
#
# Does NOT require signing credentials. Does NOT require a GUI session
# for the audit steps (1-6). Step 7 (launch attempt) is best-effort
# and non-fatal in headless contexts.
#
# Returns exit 0 on success, 1 on a launch-blocking failure.

set -euo pipefail

APP_BUNDLE="${1:?Usage: $0 <path-to-.app>}"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: ${APP_BUNDLE} is not a directory" >&2
    exit 1
fi

echo "==> 1. Bundle structure"
for req in "Contents/Info.plist" "Contents/MacOS"; do
    if [ ! -e "${APP_BUNDLE}/${req}" ]; then
        echo "  [FAIL] Missing ${req}"
        exit 1
    fi
done
echo "  [OK]"

echo "==> 2. Codesign verifies"
if ! codesign --verify --verbose=2 "${APP_BUNDLE}" >/dev/null 2>&1; then
    echo "  [FAIL] codesign --verify rejected the bundle"
    codesign --verify --verbose=2 "${APP_BUNDLE}" 2>&1 | sed 's/^/    /'
    exit 1
fi
echo "  [OK]"

echo "==> 3. Privileged entitlement audit"
ENT="/tmp/$$.verify-launch.entitlements.plist"
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
    echo "  [OK] No unauthorized privileged entitlements"
else
    echo "  [OK] No entitlements readable (unsigned)"
fi

echo "==> 4. Best-effort launch attempt (3s window)"
EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "")
EXEC_PATH="${APP_BUNDLE}/Contents/MacOS/${EXEC_NAME}"
if [ -x "${EXEC_PATH}" ]; then
    "${EXEC_PATH}" >/tmp/.vfy-launch-stdout 2>/tmp/.vfy-launch-stderr &
    PID=$!
    sleep 3
    if kill -0 $PID 2>/dev/null; then
        echo "  [OK] Binary launched and is running (pid=${PID})"
        kill $PID 2>/dev/null || true
        sleep 1
        kill -9 $PID 2>/dev/null || true
    else
        wait $PID 2>/dev/null || true
        EXIT_CODE=$?
        if [ "${EXIT_CODE}" -eq 137 ] || grep -qi "Killed" /tmp/.vfy-launch-stderr 2>/dev/null; then
            echo "  [FAIL] Binary was SIGKILLed at launch (exit ${EXIT_CODE})"
            echo "    Likely cause: AMFI refused to load (signature/entitlement mismatch)"
            echo "    Check: log show --predicate 'process == \"launchd\"' --info --debug --last 1m"
            exit 1
        else
            echo "  [WARN] Binary exited within 3s (exit ${EXIT_CODE}) — not necessarily a launch failure"
        fi
    fi
fi

echo
echo "PASS: ${APP_BUNDLE} is launchable"