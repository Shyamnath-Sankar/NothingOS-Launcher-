#!/bin/sh
# Explicit prerequisite probe for locked private-space validation.
#
# This script does NOT claim the launcher's drawer/search/recents filtering is
# verified. It only checks the device prerequisite that is safe to automate:
# a PRIVATE profile exists and is locked (quiet/stopped). The app-level UI
# assertions still require a manual or dedicated UI-test pass; see the
# "remaining manual steps" it prints and docs/agent/emulator-verification.md.
#
# Exit codes:
#   0   a locked PRIVATE profile was detected (prerequisite satisfied)
#   77  no PRIVATE profile, or it is not locked (prerequisite not met)
#   1   adb/device/command error
#
# Usage: scripts/private-space-check.sh [--artifacts DIR] [--serial SERIAL]
set -eu

usage() {
    printf 'usage: %s [--artifacts DIR] [--serial SERIAL]\n' "$0" >&2
    exit 2
}

ARTIFACTS=
SERIAL=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifacts)
            [ "$#" -ge 2 ] || usage
            ARTIFACTS=$2
            shift 2
            ;;
        --serial)
            [ "$#" -ge 2 ] || usage
            SERIAL=$2
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ -z "$ARTIFACTS" ]; then
    ARTIFACTS="$ROOT/build/private-space-check/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$ARTIFACTS"
ARTIFACTS=$(CDPATH= cd -- "$ARTIFACTS" && pwd)

adb_cmd() {
    if [ -n "$SERIAL" ]; then
        adb -s "$SERIAL" "$@"
    else
        adb "$@"
    fi
}

fail() {
    printf 'private-space-check: ERROR: %s\n' "$*" >&2
    printf 'private-space-check: evidence: %s\n' "$ARTIFACTS" >&2
    exit 1
}

skip() {
    printf 'private-space-check: SKIP (prerequisite not met): %s\n' "$*" >&2
    printf 'private-space-check: evidence: %s\n' "$ARTIFACTS" >&2
    exit 77
}

command -v adb >/dev/null 2>&1 || fail "adb is not on PATH"

if [ -z "$SERIAL" ]; then
    devices=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    device_count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$device_count" -ne 1 ]; then
        fail "expected exactly one adb device, found $device_count; pass --serial"
    fi
    SERIAL=$(printf '%s\n' "$devices" | sed -n '1p')
fi

adb_cmd get-state >/dev/null 2>&1 || fail "adb device $SERIAL is not available"

sdk=$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')
case "$sdk" in
    '' | *[!0-9]*) fail "could not read the device API level: '$sdk'" ;;
esac
if [ "$sdk" -lt 35 ]; then
    skip "API $sdk does not support private space (requires API 35+)"
fi

{
    printf 'serial=%s\n' "$SERIAL"
    adb devices -l
    adb_cmd shell getprop ro.build.version.sdk
    adb_cmd shell getprop ro.build.version.release
} > "$ARTIFACTS/device.txt" 2>&1 || fail "could not read device properties"

if ! adb_cmd shell dumpsys user > "$ARTIFACTS/dumpsys-user.txt" 2>&1; then
    fail "could not dump users"
fi

private_id=$(
    awk '
        /UserInfo\{/ {
            id = $0
            sub(/.*UserInfo\{/, "", id)
            sub(/:.*/, "", id)
        }
        /Type:.*android\.os\.usertype\.profile\.PRIVATE/ {
            if (id != "") {
                print id
                exit
            }
        }
    ' "$ARTIFACTS/dumpsys-user.txt"
)

if [ -z "$private_id" ]; then
    skip "no android.os.usertype.profile.PRIVATE user found; create a private space first"
fi

private_block=$(
    awk -v id="$private_id" '
        $0 ~ "UserInfo\\{" id ":" { inblock = 1 }
        inblock { print }
        inblock && /State:/ { exit }
    ' "$ARTIFACTS/dumpsys-user.txt"
)
printf '%s\n' "$private_block" > "$ARTIFACTS/private-user.txt"

state=$(printf '%s\n' "$private_block" | sed -n 's/^[[:space:]]*State:[[:space:]]*//p' | sed -n '1p')
flags=$(printf '%s\n' "$private_block" | sed -n 's/^[[:space:]]*Flags:[[:space:]]*//p' | sed -n '1p')
printf 'private_id=%s\nstate=%s\nflags=%s\n' "$private_id" "$state" "$flags" \
    > "$ARTIFACTS/private-state.txt"

case "$flags" in
    *QUIET_MODE*) ;;
    *)
        skip "private profile $private_id is not quiet/locked (State=$state Flags=$flags); lock the device and rerun"
        ;;
esac
if [ "$state" = "RUNNING_UNLOCKED" ]; then
    skip "private profile $private_id is RUNNING_UNLOCKED; lock the device and rerun"
fi

printf 'private-space-check: LOCKED private profile detected (id=%s, State=%s).\n' \
    "$private_id" "$state"
printf 'private-space-check: this is a prerequisite check only, not app-level validation.\n'
printf 'private-space-check: remaining manual/UI steps:\n'
printf '  1. Install an app only in the private profile while it is unlocked (e.g. adb install --user %s <apk>).\n' "$private_id"
printf '  2. Lock the private space (lock the device, or use the private-space lock action).\n'
printf '  3. In the launcher, open the app drawer and search for that app; it must not appear.\n'
printf '  4. Open Recents; private-profile tasks must not appear.\n'
printf '  5. Unlock the private space and confirm the app appears again.\n'
printf 'private-space-check: evidence: %s\n' "$ARTIFACTS"
