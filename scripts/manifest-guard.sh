#!/bin/sh
# Fail when a merged Play manifest still contains entries that AGENTS.md
# section 7 forbids. Usage: scripts/manifest-guard.sh <merged-manifest.xml>
set -eu

usage() {
    printf 'usage: %s <merged-manifest.xml>\n' "$0" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
manifest=$1

if [ ! -f "$manifest" ]; then
    printf 'manifest-guard: cannot read manifest: %s\n' "$manifest" >&2
    exit 2
fi

violations=0

check() {
    kind=$1
    pattern=$2
    if grep -Eq "android:name=\"($pattern)\"" "$manifest"; then
        printf 'manifest-guard: forbidden %s:\n' "$kind" >&2
        grep -E "android:name=\"($pattern)\"" "$manifest" >&2
        violations=$((violations + 1))
    fi
}

# Permissions (AGENTS.md section 7).
check permission 'android\.permission\.READ_CONTACTS'
check permission 'android\.permission\.READ_MEDIA_[A-Z_]+'
check permission 'android\.permission\.READ_HISTORY_BOOKMARKS'
check permission 'android\.permission\.PACKAGE_USAGE_STATS'
check permission 'android\.permission\.INTERACT_ACROSS_USERS(_FULL)?'
check permission 'android\.permission\.MANAGE_USERS'
check permission 'android\.permission\.FORCE_STOP_PACKAGES'
check permission 'android\.permission\.STATUS_BAR_SERVICE'
check permission 'android\.permission\.SUSPEND_APPS'
check permission 'com\.google\.android\.apps\.nexuslauncher\.permission\.QSB'
check permission 'com\.kieronquinn\.app\.smartspacer\.permission\.ACCESS_SMARTSPACER'

# Third-party QSB / Smartspacer components (AGENTS.md section 7).
check component 'app\.lawnchair\.smartspace\.SmartspaceAppWidgetProvider'
check component 'app\.lawnchair\.smartspace\.SmartspacePreferencesShortcut'

if [ "$violations" -ne 0 ]; then
    printf 'manifest-guard: FAIL: %s still contains %d forbidden entry/entries.\n' \
        "$manifest" "$violations" >&2
    printf 'manifest-guard: see AGENTS.md section 7 (Play Store compliance invariants).\n' >&2
    exit 1
fi

printf 'manifest-guard: OK: %s contains no forbidden permissions/components\n' "$manifest"
