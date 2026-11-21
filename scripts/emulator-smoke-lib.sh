#!/bin/sh
# Pure helpers shared by scripts/emulator-smoke.sh and its regression test.
#
# These functions only read files; they never touch adb. That keeps the
# foreground and UIAutomator parsing logic unit-testable with captured
# artifacts instead of a live emulator.
#
# Every helper runs in a subshell so its variables cannot clobber a caller's
# loop state (POSIX sh has no portable `local`).

# Run a command with a bounded wall-clock timeout. GNU timeout is used when
# available; otherwise the command runs in the background and is killed after
# the limit. The diagnostic names the operation so a hung adb/uiautomator call
# is visible in the evidence log.
run_with_timeout() (
    rwt_seconds=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        rwt_status=0
        timeout "$rwt_seconds" "$@" || rwt_status=$?
        if [ "$rwt_status" -eq 124 ]; then
            printf 'run_with_timeout: timed out after %ss: %s\n' \
                "$rwt_seconds" "$*" >&2
        fi
        exit "$rwt_status"
    fi
    "$@" &
    rwt_pid=$!
    (
        sleep "$rwt_seconds"
        kill -TERM "$rwt_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$rwt_pid" 2>/dev/null || true
    ) &
    rwt_watch=$!
    rwt_status=0
    wait "$rwt_pid" || rwt_status=$?
    kill "$rwt_watch" 2>/dev/null || true
    wait "$rwt_watch" 2>/dev/null || true
    if [ "$rwt_status" -eq 143 ] || [ "$rwt_status" -eq 137 ]; then
        printf 'run_with_timeout: timed out after %ss: %s\n' \
            "$rwt_seconds" "$*" >&2
    fi
    exit "$rwt_status"
)

# Print the component of the live resumed activity from a
# `dumpsys activity activities` dump.
#
# `topResumedActivity` is authoritative; `mResumedActivity` is the fallback.
# Historical task records also mention package names, so only these two fields
# may be treated as "foreground".
resumed_component() (
    dump=$1
    for field in topResumedActivity mResumedActivity; do
        component=$(grep -E "(^|[[:space:]])$field[=:]" "$dump" |
            sed -n 's/.*[ {]\([A-Za-z0-9_][A-Za-z0-9_.]*\/[A-Za-z0-9_.$][A-Za-z0-9_.$]*\).*/\1/p' |
            sed -n '1p' || true)
        if [ -n "$component" ]; then
            printf '%s\n' "$component"
            return 0
        fi
    done
    return 0
)

# Succeed only when the resumed component belongs to exactly the given package.
# The trailing slash keeps com.android.settings from matching
# com.android.settings.intelligence.
foreground_is() (
    dump=$1
    expected_pkg=$2
    component=$(resumed_component "$dump")
    case "$component" in
        "$expected_pkg"/*) return 0 ;;
        *) return 1 ;;
    esac
)

# Print the root bounds ("x1 y1 x2 y2") of a UIAutomator XML dump. UIAutomator
# emits the window root as the first node, so its bounds are the visible display
# area for this capture (insets included, unlike a fixed wm-size assumption).
ui_root_bounds() (
    xml=$1
    [ -s "$xml" ] || return 0
    tr '>' '\n' < "$xml" |
        sed -n 's/.*bounds="\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]".*/\1 \2 \3 \4/p' |
        sed -n '1p'
)

# Print the top y of the lowest labelled row (the hotseat/dock) from a
# UIAutomator dump, using the root bounds to exclude the upper workspace. The
# row is found by position, not by a hard-coded app name, so it survives
# emulator locale changes. Prints nothing when the dump exposes no such row.
ui_dock_top() (
    xml=$1
    root=$2
    [ -s "$xml" ] || return 0
    [ -n "$root" ] || return 0
    set -- $root
    root_y1=$2
    root_h=$(($4 - $2))
    [ "$root_h" -gt 0 ] || return 0
    threshold=$((root_y1 + root_h * 55 / 100))
    tr '>' '\n' < "$xml" |
        awk -v threshold="$threshold" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function y1_of(b,    s, n, p) {
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return p[2] + 0
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                bounds = attr($0, "bounds")
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (bounds == "" || (text == "" && desc == "")) next
                y = y1_of(bounds)
                if (y < threshold) next
                if (best == "" || y < best) best = y
            }
            END {
                if (best != "") print best
            }
        '
)

# Print the bottom y of the lowest labelled row (the hotseat/dock) from a
# UIAutomator dump. This complements ui_dock_top: together they bound the dock
# icon band so a swipe can start in the empty gutter below it. When the QSB top
# is supplied, anything at or below it is excluded so the search widget cannot
# be mistaken for the dock.
ui_dock_bottom() (
    xml=$1
    root=$2
    qsb_top=${3:-}
    [ -s "$xml" ] || return 0
    [ -n "$root" ] || return 0
    set -- $root
    root_y1=$2
    root_h=$(($4 - $2))
    [ "$root_h" -gt 0 ] || return 0
    threshold=$((root_y1 + root_h * 55 / 100))
    case "$qsb_top" in '' | *[!0-9]*) qsb_top= ;; esac
    tr '>' '\n' < "$xml" |
        awk -v threshold="$threshold" -v qsb_top="$qsb_top" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function y_of(b, field,    s, n, p) {
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return p[field] + 0
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                bounds = attr($0, "bounds")
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (bounds == "" || (text == "" && desc == "")) next
                y1 = y_of(bounds, 2)
                if (y1 < threshold) next
                if (qsb_top != "" && y1 >= qsb_top) next
                y2 = y_of(bounds, 4)
                if (y2 > best) best = y2
            }
            END {
                if (best > 0) print best
            }
        '
)

# Print the top y of the QSB/search container when the dump exposes it. The
# id is checked as a path suffix so both the Play applicationId and the
# inherited github/nightly package work.
ui_qsb_top() (
    xml=$1
    [ -s "$xml" ] || return 0
    tr '>' '\n' < "$xml" |
        awk '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function y_of(b, field,    s, n, p) {
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return p[field] + 0
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                if (rid !~ /(^|\/)search_container_workspace$/) next
                bounds = attr($0, "bounds")
                if (bounds == "") next
                y1 = y_of(bounds, 2)
                if (y1 >= 0) {
                    print y1
                    exit
                }
            }
        '
)

# Succeed when a swipe covers more than half of the display height. The
# launcher's shift range equals the display height on phones; at zero release
# velocity the drawer only commits above 40 percent, so a half-screen floor
# leaves room for touch slop and the final MOVE sample.
drawer_swipe_is_long_enough() (
    height=$1
    start_y=$2
    end_y=$3
    case "$height" in '' | *[!0-9]*) return 1 ;; esac
    case "$start_y" in '' | *[!0-9]*) return 1 ;; esac
    case "$end_y" in '' | *[!0-9]*) return 1 ;; esac
    [ "$height" -gt 0 ] || return 1
    travel=$((start_y - end_y))
    [ "$travel" -gt $((height / 2)) ]
)

# Print the fraction of the display height covered by a swipe, for geometry
# regressions. This is the raw travel, before touch slop is subtracted.
drawer_swipe_travel_fraction() (
    height=$1
    start_y=$2
    end_y=$3
    case "$height" in '' | *[!0-9]*) return 1 ;; esac
    case "$start_y" in '' | *[!0-9]*) return 1 ;; esac
    case "$end_y" in '' | *[!0-9]*) return 1 ;; esac
    [ "$height" -gt 0 ] || return 1
    travel=$((start_y - end_y))
    awk -v travel="$travel" -v height="$height" \
        'BEGIN { printf "%.4f\n", travel / height }'
)

# Compute a safe upward swipe for opening the app drawer. $1/$2 are the
# measured display width/height; $3 is the measured hotseat top, $4 the dock
# icon bottom and $5 the QSB top (all optional).
#
# When the hierarchy exposes the dock icon band and the QSB, start in the empty
# gutter between them and end near the top of the display. That gives the
# zero-velocity drawer drag more than half the shift range instead of the old
# ~42 percent that snapped back. Without those measurements, start above the
# dock as before. The x is the horizontal centre: the start row is below every
# dock icon, so no icon can consume the DOWN. Prints "x1 y1 x2 y2".
drawer_swipe_target() (
    width=$1
    height=$2
    hotseat_top=${3:-}
    dock_bottom=${4:-}
    qsb_top=${5:-}
    case "$width" in '' | *[!0-9]*) return 1 ;; esac
    case "$height" in '' | *[!0-9]*) return 1 ;; esac
    [ "$width" -gt 0 ] && [ "$height" -gt 0 ] || return 1
    x=$((width / 2))
    end_y=$((height * 5 / 100))
    margin=$((height / 10))
    min_gap=$((height * 2 / 100))
    case "$dock_bottom" in '' | *[!0-9]*) dock_bottom= ;; esac
    case "$qsb_top" in '' | *[!0-9]*) qsb_top= ;; esac
    start_y=
    if [ -n "$dock_bottom" ] && [ -n "$qsb_top" ] &&
        [ "$qsb_top" -gt "$dock_bottom" ] &&
        [ $((qsb_top - dock_bottom)) -ge "$min_gap" ]; then
        start_y=$(((dock_bottom + qsb_top) / 2))
    elif [ -n "$hotseat_top" ] && [ "$hotseat_top" -gt 0 ] &&
        [ "$hotseat_top" -le "$height" ]; then
        start_y=$((hotseat_top - margin))
    else
        start_y=$((height * 60 / 100))
    fi
    if [ "$start_y" -le "$end_y" ]; then
        return 1
    fi
    drawer_swipe_is_long_enough "$height" "$start_y" "$end_y" || return 1
    printf '%s %s %s %s\n' "$x" "$start_y" "$x" "$end_y"
)

# Succeed only when the UIAutomator dump shows an actual app-drawer search
# input or app-list container. The launcher inflates these while HOME is
# visible too, so their mere presence in source is not enough. When a
# reference HOME dump is supplied, the drawer must also differ from it; this
# rejects the CI68 case where a swipe did nothing and the dump stayed
# byte-identical to HOME.
drawer_is_ready() (
    xml=$1
    reference=${2:-}
    [ -s "$xml" ] || return 1
    if [ -n "$reference" ] && cmp -s "$reference" "$xml"; then
        return 1
    fi
    if grep -Eq 'resource-id="[^"]*/(input|search_container_all_apps)"' "$xml" ||
        grep -Fq 'android.widget.EditText' "$xml" ||
        grep -Fq 'AllAppsSearchInput' "$xml"; then
        return 0
    fi
    if grep -Eq 'resource-id="[^"]*/(apps_list_view|apps_list_view_work)"' "$xml" ||
        grep -Fq 'SearchContainerView' "$xml"; then
        return 0
    fi
    return 1
)

# Print the bounds ("x1 y1 x2 y2") of the clickable node that represents the
# app labelled $2 in a UIAutomator XML dump. A clickable node that matches
# directly wins; otherwise the nearest clickable ancestor of any matching node
# is preferred over a bare non-clickable label. This avoids tapping an earlier
# "Settings" header instead of the real app result. Returns nothing when no
# node carries that exact text or content description.
ui_clickable_label_bounds() (
    xml=$1
    label=$2
    [ -s "$xml" ] || return 0
    tr '>' '\n' < "$xml" |
        awk -v label="$label" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function emit(b,    s, p, n) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return
                s = b
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n == 4) print p[1], p[2], p[3], p[4]
            }
            {
                if ($0 ~ /<\/node/) {
                    if (sp > 0) sp--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                bounds = attr($0, "bounds")
                clickable = attr($0, "clickable")
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                if (!selfclose) {
                    sp++
                    stack[sp] = (clickable == "true" && bounds != "") ? bounds : ""
                }
                if (text != label && desc != label) next
                if (clickable == "true" && bounds != "") {
                    emit(bounds)
                    found = 1
                    exit
                }
                ancestor = ""
                for (i = sp; i >= 1; i--) {
                    if (stack[i] != "") {
                        ancestor = stack[i]
                        break
                    }
                }
                if (ancestor != "") {
                    if (best == "") best = ancestor
                } else if (bounds != "" && fallback == "") {
                    fallback = bounds
                }
            }
            END {
                if (found) exit
                if (best != "") emit(best)
                else if (fallback != "") emit(fallback)
            }
        '
)
