#!/bin/sh
# Verify the assembled Play debug build.
#
# 1. Runs the existing identity/manifest guard fixture suites (no Gradle needed).
# 2. Locates the Gradle-merged lawnWithQuickstepPlayDebug manifest produced by
#    assembleLawnWithQuickstepPlayDebug, failing closed when it is missing or
#    ambiguous.
# 3. Runs manifest-guard.sh against that merged manifest.
# 4. Checks the resolved package and provider authorities, allowing for the
#    existing debug applicationIdSuffix.
#
# Usage: scripts/verify-play-build.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

if [ ! -d "$ROOT" ]; then
    printf 'verify-play-build: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
fi

fail() {
    printf 'verify-play-build: %s\n' "$*" >&2
    exit 1
}

# 1. Guard fixture suites.
sh "$SCRIPT_DIR/play-identity-guard-test.sh"
sh "$SCRIPT_DIR/manifest-guard-test.sh"

# Identity of the source tree (build.gradle + source manifests).
sh "$SCRIPT_DIR/play-identity-guard.sh" "$ROOT"

# 2. Locate the merged manifest for the Play debug variant.
INTERMEDIATES="$ROOT/build/intermediates"
if [ ! -d "$INTERMEDIATES" ]; then
    fail "missing $INTERMEDIATES; run ./gradlew assembleLawnWithQuickstepPlayDebug first"
fi

candidates=$(
    # AGP emits an intermediate MainManifest and a final Manifest. Prefer the
    # final output; use the older singular directory only when final is absent.
    for dir in merged_manifests merged_manifest; do
        [ -d "$INTERMEDIATES/$dir" ] || continue
        matches=$(find "$INTERMEDIATES/$dir" -type f -name AndroidManifest.xml 2>/dev/null |
            grep -F '/lawnWithQuickstepPlayDebug/' | sort -u || true)
        if [ -n "$matches" ]; then
            printf '%s\n' "$matches"
            break
        fi
    done
)
count=$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$count" -eq 0 ]; then
    fail "no merged manifest found for lawnWithQuickstepPlayDebug under $INTERMEDIATES; run ./gradlew assembleLawnWithQuickstepPlayDebug first"
fi
if [ "$count" -gt 1 ]; then
    printf '%s\n' "$candidates" >&2
    fail "ambiguous merged manifest candidates ($count); expected exactly one"
fi

merged=$candidates
[ -f "$merged" ] || fail "merged manifest is not a file: $merged"

# 3. Play manifest guard.
sh "$SCRIPT_DIR/manifest-guard.sh" "$merged"

# 4. Resolved identity and provider authorities.
play_id=$(
    awk '
        /^[[:space:]]*play[[:space:]]*\{/ { inblock = 1; next }
        inblock && /^[[:space:]]*\}/ { inblock = 0 }
        inblock && /applicationId/ { print; exit }
    ' "$ROOT/build.gradle" |
        sed -n "s/.*applicationId[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p"
)
debug_suffix=$(
    awk '
        /^[[:space:]]*debug[[:space:]]*\{/ { inblock = 1; next }
        inblock && /^[[:space:]]*\}/ { inblock = 0 }
        inblock && /applicationIdSuffix/ { print; exit }
    ' "$ROOT/build.gradle" |
        sed -n "s/.*applicationIdSuffix[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p"
)

[ -n "$play_id" ] || fail "could not read the Play applicationId from $ROOT/build.gradle"
expected_id="$play_id$debug_suffix"

manifest_tag=$(tr '\n' ' ' < "$merged" | grep -oE '<manifest[^>]*>' | head -1)
actual_id=$(printf '%s' "$manifest_tag" | sed -n 's/.*package="\([^"]*\)".*/\1/p')
[ -n "$actual_id" ] || fail "could not read the package from $merged"

if [ "$actual_id" != "$expected_id" ]; then
    fail "merged package is '$actual_id', expected '$expected_id' (Play id '$play_id' + debug suffix '$debug_suffix')"
fi

authorities=$(
    grep -oE 'android:authorities="[^"]*"' "$merged" |
        sed -E 's/android:authorities="([^"]*)"/\1/' |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
        sed '/^$/d' || true
)

violations=0
for authority in $authorities; do
    case "$authority" in
        "$expected_id" | "$expected_id".*) ;;
        *)
            printf 'verify-play-build: provider authority is not derived from %s: %s\n' \
                "$expected_id" "$authority" >&2
            violations=$((violations + 1))
            ;;
    esac
done

[ "$violations" -eq 0 ] ||
    fail "$violations provider authorit(y/ies) are not derived from $expected_id"

printf 'verify-play-build: OK: %s is Play-safe with package %s\n' "$merged" "$actual_id"
