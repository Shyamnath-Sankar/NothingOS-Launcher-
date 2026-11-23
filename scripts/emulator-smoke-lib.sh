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

# Succeed only when the resumed component is exactly <package>/<class>. The
# expected class may be the leading-dot shorthand (".Foo") or fully qualified.
# A package-only match is not enough: another activity in the same package must
# not satisfy an exact-activity claim.
foreground_is_component() (
    dump=$1
    expected_pkg=$2
    expected_cls=$3
    [ -n "$expected_pkg" ] || return 1
    [ -n "$expected_cls" ] || return 1
    component=$(resumed_component "$dump")
    case "$component" in
        */*) ;;
        *) return 1 ;;
    esac
    actual_pkg=${component%%/*}
    actual_cls=${component#*/}
    [ "$actual_pkg" = "$expected_pkg" ] || return 1
    case "$expected_cls" in
        .*) expected_full="$expected_pkg$expected_cls" ;;
        *) expected_full=$expected_cls ;;
    esac
    case "$actual_cls" in
        .*) actual_full="$actual_pkg$actual_cls" ;;
        *) actual_full=$actual_cls ;;
    esac
    [ "$actual_full" = "$expected_full" ]
)

# Extract the first package/class component from `cmd package resolve-activity`
# output. A brief dump normally prints the component alone; the fallback accepts
# the component token after the priority/match fields. "No activity found" and
# other prose contain no slash and yield nothing, so a caller can apply its own
# safe fallback rather than guessing an activity alias.
parse_resolved_component() (
    out=$1
    component=$(printf '%s\n' "$out" |
        sed -n 's/^\([A-Za-z0-9_][A-Za-z0-9_.]*\/[A-Za-z0-9_.$][A-Za-z0-9_.$]*\)$/\1/p' |
        sed -n '1p')
    if [ -z "$component" ]; then
        component=$(printf '%s\n' "$out" |
            sed -n 's/.*[[:space:]]\([A-Za-z0-9_][A-Za-z0-9_.]*\/[A-Za-z0-9_.$][A-Za-z0-9_.$]*\).*/\1/p' |
            sed -n '1p')
    fi
    printf '%s\n' "$component"
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

# Print "x1 y1 x2 y2" for a UIAutomator bounds string "[x1,y1][x2,y2]". Prints
# nothing for a malformed value.
ui_bounds_values() (
    printf '%s\n' "${1:-}" |
        sed -n 's/^\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]$/\1 \2 \3 \4/p'
)

# Print one attribute of the first UIAutomator node whose resource-id ends with
# /<suffix>. The dump may be a single physical line, so it is split into node
# records first. Prints nothing when the child is not exposed.
ui_node_attribute() (
    xml=$1
    id_suffix=$2
    attribute=$3
    [ -s "$xml" ] || return 0
    tr '>' '\n' < "$xml" |
        awk -v id_suffix="$id_suffix" -v attribute="$attribute" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            {
                if (found) exit
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                if (rid !~ ("(^|/)" id_suffix "$")) next
                print attr($0, attribute)
                found = 1
            }
        '
)

home_widget_clock_text() (
    ui_node_attribute "$1" nothingui_clock_time text
)

home_widget_battery_description() (
    ui_node_attribute "$1" nothingui_battery_art content-desc
)

# The clock text must be the live TextClock value, not an expected constant.
home_widget_clock_text_is_live() (
    printf '%s\n' "$1" | grep -Eq '^[0-9]{1,2}:[0-9]{2}$'
)

# The battery description must be a real 0..100 percentage or the explicit
# unknown `--` fallback; an arbitrary or fabricated number is rejected.
home_widget_battery_description_is_real() (
    value=$1
    case "$value" in
        -- | --,\ charging) return 0 ;;
    esac
    case "$value" in
        *,\ charging) value=${value%, charging} ;;
    esac
    case "$value" in
        *%) percent=${value%\%} ;;
        *) return 1 ;;
    esac
    case "$percent" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$percent" -le 100 ]
)

home_widget_device_storage_value() (
    ui_node_attribute "$1" nothingui_device_storage_value text
)

home_widget_device_storage_detail() (
    ui_node_attribute "$1" nothingui_device_storage_detail text
)

# Print the measured bounds of one real device-card Settings pill. The child id
# is the RemoteViews click target, so the smoke taps the actual rendered bounds
# rather than a fixed coordinate.
home_widget_device_action_bounds() (
    xml=$1
    action=$2
    case "$action" in
        wifi | sound | display) ;;
        *) return 0 ;;
    esac
    ui_node_attribute "$xml" "nothingui_device_$action" bounds |
        sed -n 's/^\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]$/\1 \2 \3 \4/p'
)

# The device card must show either a real formatted free-space reading (for
# example "83.0 GB free") or the honest unknown pair: the short "--" marker as
# the large value and the localized "Storage unavailable" message as detail. A
# fabricated percentage, the old wide unknown label in the value slot, a blank
# label or a catalog string is rejected.
home_widget_device_storage_is_real() (
    value=$1
    detail=${2:-}
    case "$value" in
        --) [ "$detail" = 'Storage unavailable' ] && return 0 ;;
    esac
    printf '%s\n' "$value" | grep -Eq '^[0-9]+([.][0-9]+)? [KMGTP]?B free$'
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
# icon band so a swipe can start in the empty gutter below it. The bottom is
# taken only from nodes in the same row as ui_dock_top, so the bottom QSB's
# "Search" nodes cannot be mistaken for dock icons even when they carry no
# resource-id. Search containers (the workspace header and any bottom QSB) are
# also excluded by resource-id. When the QSB top is supplied, anything at or
# below it is excluded.
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
    row_tolerance=$((root_h * 2 / 100))
    case "$qsb_top" in '' | *[!0-9]*) qsb_top= ;; esac
    tr '>' '\n' < "$xml" |
        awk -v threshold="$threshold" -v qsb_top="$qsb_top" \
            -v row_tolerance="$row_tolerance" '
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
                if (rid ~ /(^|\/)search_container_workspace$/) next
                bounds = attr($0, "bounds")
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (bounds == "" || (text == "" && desc == "")) next
                y1 = y_of(bounds, 2)
                if (y1 < threshold) next
                if (qsb_top != "" && y1 >= qsb_top) next
                count++
                row_top[count] = y1
                row_bottom[count] = y_of(bounds, 4)
            }
            END {
                dock_top = -1
                for (i = 1; i <= count; i++) {
                    if (dock_top < 0 || row_top[i] < dock_top) {
                        dock_top = row_top[i]
                    }
                }
                if (dock_top < 0) exit
                for (i = 1; i <= count; i++) {
                    if (row_top[i] <= dock_top + row_tolerance &&
                        row_bottom[i] > best) {
                        best = row_bottom[i]
                    }
                }
                if (best > 0) print best
            }
        '
)

# Print the top y of the bottom QSB/search container when the dump exposes it.
# The id is checked as a path suffix so both the Play applicationId and the
# inherited github/nightly package work. A search container above the measured
# dock bottom is the workspace header, not the bottom QSB, so it is rejected:
# the candidate must start below $2. Without a numeric dock bottom there is no
# way to tell the header from the QSB, so nothing is printed.
ui_qsb_top() (
    xml=$1
    dock_bottom=${2:-}
    [ -s "$xml" ] || return 0
    case "$dock_bottom" in '' | *[!0-9]*) return 0 ;; esac
    tr '>' '\n' < "$xml" |
        awk -v dock_bottom="$dock_bottom" '
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
                if (y1 > dock_bottom) {
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
# icon bottom and $5 the bottom QSB top (all optional).
#
# When the hierarchy exposes the dock icon band and a bottom QSB, start in the
# empty gutter between them and end near the top of the display. When only the
# dock icon band is exposed (the bottom QSB is not in UIAutomator on the actual
# HOME), start a quarter of the measured icon band below the icon bottom: the
# visible gutter above the QSB. Both give the zero-velocity drawer drag more
# than half the shift range instead of the old ~42 percent that snapped back.
# Without those measurements, start above the dock as before. The x is the
# horizontal centre: the start row is below every dock icon, so no icon can
# consume the DOWN. Prints "x1 y1 x2 y2".
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
    elif [ -n "$dock_bottom" ] && [ -n "$hotseat_top" ] &&
        [ "$hotseat_top" -gt 0 ] && [ "$dock_bottom" -gt "$hotseat_top" ] &&
        [ "$dock_bottom" -lt "$height" ]; then
        icon_band=$((dock_bottom - hotseat_top))
        start_y=$((dock_bottom + icon_band / 4))
        if [ "$start_y" -ge "$height" ]; then
            start_y=$((hotseat_top - margin))
        fi
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

# Print the navigation-bar bounds ("x1 y1 x2 y2") from a `dumpsys window`
# dump. The NavigationBar window is a separate SystemUI window, so its frame is
# the authoritative safe-area edge for the edge-to-edge launcher drawer. When
# the window frame is absent, use the measured modern InsetsSource
# `type=navigationBars` frame, then the stable display frame (`mStable=Rect(...)`)
# and the current display frame (`mCurrent=Rect(...)`).
# Prints nothing when no source is measurable, so the caller can fail closed
# instead of guessing a coordinate.
ui_navigation_bar_bounds() (
    dump=$1
    [ -s "$dump" ] || return 0
    nav=$(awk '
        /^[[:space:]]*Window #[0-9]+ Window\{/ {
            nav = ($0 ~ /NavigationBar/)
            next
        }
        nav && /mFrame=\[/ {
            line = $0
            if (match(line, /mFrame=\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]/)) {
                b = substr(line, RSTART + 7, RLENGTH - 7)
                gsub(/[^0-9]+/, " ", b)
                sub(/^ +/, "", b)
                sub(/ +$/, "", b)
                n = split(b, p, / +/)
                if (n == 4) {
                    print p[1], p[2], p[3], p[4]
                    exit
                }
            }
        }
    ' "$dump")
    if [ -n "$nav" ]; then
        printf '%s\n' "$nav"
        return 0
    fi
    nav=$(awk '
        /InsetsSource/ && /type=navigationBars/ && /visible=true/ {
            line = $0
            if (match(line, /frame=\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]/)) {
                b = substr(line, RSTART + 7, RLENGTH - 7)
                gsub(/[^0-9]+/, " ", b)
                sub(/^ +/, "", b)
                sub(/ +$/, "", b)
                if (split(b, p, / +/) == 4) {
                    print p[1], p[2], p[3], p[4]
                    exit
                }
            }
            if (match(line, /frame=Rect\([0-9]+, *[0-9]+ *- *[0-9]+, *[0-9]+\)/)) {
                b = substr(line, RSTART + 10, RLENGTH - 10)
                gsub(/[^0-9]+/, " ", b)
                sub(/^ +/, "", b)
                sub(/ +$/, "", b)
                if (split(b, p, / +/) == 4) {
                    print p[1], p[2], p[3], p[4]
                    exit
                }
            }
        }
    ' "$dump")
    if [ -n "$nav" ]; then
        printf '%s\n' "$nav"
        return 0
    fi
    awk '
        /mCurrent=Rect\(/ {
            line = $0
            sub(/^.*mCurrent=Rect\(/, "", line)
            sub(/\).*$/, "", line)
            gsub(/[^0-9]+/, " ", line)
            sub(/^ +/, "", line)
            sub(/ +$/, "", line)
            if (split(line, c, / +/) == 4) {
                cur_right = c[3]
                cur_bottom = c[4]
            }
        }
        /mStable=Rect\(/ {
            line = $0
            sub(/^.*mStable=Rect\(/, "", line)
            sub(/\).*$/, "", line)
            gsub(/[^0-9]+/, " ", line)
            sub(/^ +/, "", line)
            sub(/ +$/, "", line)
            if (split(line, s, / +/) == 4) stable_bottom = s[4]
        }
        END {
            if (cur_bottom <= 0) exit
            if (stable_bottom <= 0 || stable_bottom > cur_bottom) {
                stable_bottom = cur_bottom
            }
            print 0, stable_bottom, cur_right, cur_bottom
        }
    ' "$dump"
)


# Print "home lock" wallpaper IDs from a `dumpsys wallpaper` dump. Home is
# required; the lock ID prints as "-" when the dump has no separate lock row.
#
# Current AOSP (WallpaperManagerService.dump/dumpWallpaper) emits three
# sections -- "System wallpaper state:", "Lock wallpaper state:" and
# "Fallback wallpaper state:" -- and each entry is
#   " User <userId>: id=<wallpaperId>: mWhich=...: mSystemWasBoth=...: ...".
# Parse only the System and Lock sections for the current user; the fallback
# section and other users are ignored. The current user may be passed as $2;
# when omitted the dump is accepted only if it has exactly one System user.
# Compatible legacy fixtures ("Home wallpaper ID", `mWallpaperId`,
# `mLockWallpaperId`) are still honoured only when no current System section is
# present. Prints nothing and fails closed on missing or ambiguous evidence.
wallpaper_ids_from_dump() (
    dump=$1
    want_user=${2:-}
    [ -s "$dump" ] || return 0
    awk -v want_user="$want_user" '
        BEGIN {
            section = ""
            sys_seen = 0
            lock_seen = 0
            n_sys = 0
            explicit_home = -1
            plain_home = -1
            legacy_lock = -1
        }
        function id_of(s,    v) {
            gsub(/[^0-9]/, "", s)
            if (s == "") return -1
            return s + 0
        }
        {
            l = tolower($0)
            if (l ~ /^[[:space:]]*system wallpaper state:/) {
                section = "system"
                sys_seen = 1
                next
            }
            if (l ~ /^[[:space:]]*lock wallpaper state:/) {
                section = "lock"
                lock_seen = 1
                next
            }
            if (l ~ /^[[:space:]]*fallback wallpaper state:/) {
                section = "fallback"
                next
            }
            if (match($0, /User[[:space:]]+[0-9]+:[[:space:]]*id=[0-9]+/)) {
                row = substr($0, RSTART, RLENGTH)
                u = row
                sub(/^User[[:space:]]+/, "", u)
                sub(/:.*/, "", u)
                v = row
                sub(/^.*id=/, "", v)
                v = id_of(v)
                if (v >= 0) {
                    if (section == "system") {
                        if (!(u in sys)) n_sys++
                        sys[u] = v
                    } else if (section == "lock") {
                        lock_ids[u] = v
                    }
                }
                next
            }
            if (section == "system" || section == "lock" || section == "fallback") next
            if (l ~ /lock/ && l ~ /wallpaper/) {
                if (match(l, /(lock wallpaper id|mlockwallpaperid|mlastlockwallpaperid)[^0-9]*[0-9]+/)) {
                    v = id_of(substr(l, RSTART, RLENGTH))
                    if (v >= 0) legacy_lock = v
                }
                next
            }
            if (match(l, /home wallpaper id[^0-9]*[0-9]+/)) {
                v = id_of(substr(l, RSTART, RLENGTH))
                if (v >= 0 && explicit_home < 0) explicit_home = v
                next
            }
            if (match(l, /mwallpaperid[^0-9]*[0-9]+/)) {
                v = id_of(substr(l, RSTART, RLENGTH))
                if (v >= 0 && plain_home < 0) plain_home = v
            }
        }
        END {
            if (sys_seen) {
                user = want_user
                if (user == "") {
                    if (n_sys != 1) exit 1
                    for (u in sys) {
                        user = u
                        break
                    }
                }
                if (!(user in sys)) exit 1
                home = sys[user]
                if (home < 0) exit 1
                if (lock_seen) {
                    lock = (user in lock_ids) ? lock_ids[user] : "-"
                } else {
                    lock = (legacy_lock >= 0) ? legacy_lock : "-"
                }
                print home, lock
                exit
            }
            home = (explicit_home >= 0) ? explicit_home : plain_home
            if (home < 0) exit 1
            lock = (legacy_lock >= 0) ? legacy_lock : "-"
            print home, lock
        }
    ' "$dump"
)

# A Home-only FLAG_SYSTEM change may share the lock image with the prior Home
# wallpaper. A recorded lock ID must not move. When the prior lock was shared
# or absent (reported as "-"), the old Home image is preserved only if it
# materialises as a lock ID equal to the prior Home ID; a still-absent lock
# after a changed Home is not proof that the lock image survived. Anything
# else means the Home-only operation changed the lock target.
wallpaper_lock_preserved() (
    before_home=$1
    before_lock=$2
    after_lock=$3
    [ -n "$before_home" ] && [ -n "$before_lock" ] && [ -n "$after_lock" ] || return 1
    if [ "$before_lock" = '-' ]; then
        [ "$after_lock" = "$before_home" ]
        return
    fi
    [ "$after_lock" = "$before_lock" ]
)

# Print the measured bounds ("x1 y1 x2 y2") of the real all-apps list container.
drawer_list_bounds() (
    xml=$1
    [ -s "$xml" ] || return 0
    for id in apps_list_view apps_list_view_work; do
        values=$(ui_bounds_values "$(ui_node_attribute "$xml" "$id" bounds)")
        if [ -n "$values" ]; then
            printf '%s\n' "$values"
            return 0
        fi
    done
)

# Print the bounds ("x1 y1 x2 y2") of the lowest labelled clickable row inside
# the measured list container. This is the final visible app row, not the fast
# scroller letters or section headers (they are not clickable). Prints nothing
# when no row is fully inside the container.
drawer_last_row_bounds() (
    xml=$1
    list=$2
    [ -s "$xml" ] || return 0
    [ -n "$list" ] || return 0
    set -- $list
    lx1=$1
    ly1=$2
    lx2=$3
    ly2=$4
    tr '>' '\n' < "$xml" |
        awk -v lx1="$lx1" -v ly1="$ly1" -v lx2="$lx2" -v ly2="$ly2" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function v_of(b, field,    s, n, p) {
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return p[field] + 0
            }
            {
                if ($0 ~ /<\/node/) {
                    if (depth > 0) depth--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                rid = attr($0, "resource-id")
                if (!selfclose) {
                    depth++
                    stack[depth] = (rid ~ /(^|\/)(apps_list_view|apps_list_view_work)$/) ||
                        (depth > 1 && stack[depth - 1])
                }
                if (!(depth > 0 && stack[depth])) next
                if (attr($0, "clickable") != "true") next
                if (attr($0, "text") == "" && attr($0, "content-desc") == "") next
                b = attr($0, "bounds")
                if (b == "") next
                x1 = v_of(b, 1)
                y1 = v_of(b, 2)
                x2 = v_of(b, 3)
                y2 = v_of(b, 4)
                if (x1 < lx1 || x2 > lx2 || y1 < ly1 || y2 > ly2) next
                if (y2 > best_bottom) {
                    best_bottom = y2
                    best_x1 = x1
                    best_y1 = y1
                    best_x2 = x2
                }
            }
            END {
                if (best_bottom > 0) print best_x1, best_y1, best_x2, best_bottom
            }
        '
)

# Print a stable signature of the labelled clickable rows inside the list. The
# smoke compares consecutive signatures to prove a bounded scroll reached the
# true end instead of assuming a fixed swipe count.
drawer_scroll_signature() (
    xml=$1
    list=$2
    [ -s "$xml" ] || return 0
    [ -n "$list" ] || return 0
    set -- $list
    lx1=$1
    ly1=$2
    lx2=$3
    ly2=$4
    tr '>' '\n' < "$xml" |
        awk -v lx1="$lx1" -v ly1="$ly1" -v lx2="$lx2" -v ly2="$ly2" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function v_of(b, field,    s, n, p) {
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return p[field] + 0
            }
            {
                if ($0 ~ /<\/node/) {
                    if (depth > 0) depth--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                rid = attr($0, "resource-id")
                if (!selfclose) {
                    depth++
                    stack[depth] = (rid ~ /(^|\/)(apps_list_view|apps_list_view_work)$/) ||
                        (depth > 1 && stack[depth - 1])
                }
                if (!(depth > 0 && stack[depth])) next
                if (attr($0, "clickable") != "true") next
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (text == "" && desc == "") next
                b = attr($0, "bounds")
                if (b == "") next
                x1 = v_of(b, 1)
                y1 = v_of(b, 2)
                x2 = v_of(b, 3)
                y2 = v_of(b, 4)
                if (x1 < lx1 || x2 > lx2 || y1 < ly1 || y2 > ly2) next
                label = (text != "") ? text : desc
                printf "%s %s %s\n", y1, y2, label
            }
        ' |
        sort
)

# Compute an upward scroll gesture ("x1 y1 x2 y2") inside the measured list and
# above the measured navigation bar. Prints nothing for a degenerate list or
# when the safe band is too small.
drawer_scroll_swipe_target() (
    list=$1
    nav_top=${2:-}
    [ -n "$list" ] || return 1
    set -- $list
    lx1=$1
    ly1=$2
    lx2=$3
    ly2=$4
    case "$lx1" in '' | *[!0-9]*) return 1 ;; esac
    case "$ly1" in '' | *[!0-9]*) return 1 ;; esac
    case "$lx2" in '' | *[!0-9]*) return 1 ;; esac
    case "$ly2" in '' | *[!0-9]*) return 1 ;; esac
    safe_bottom=$ly2
    case "$nav_top" in
        '' | *[!0-9]*) ;;
        *) [ "$nav_top" -lt "$safe_bottom" ] && safe_bottom=$nav_top ;;
    esac
    [ "$safe_bottom" -gt "$ly1" ] || return 1
    x=$(((lx1 + lx2) / 2))
    height=$((safe_bottom - ly1))
    margin=$((height / 8))
    [ "$margin" -gt 0 ] || margin=1
    start_y=$((safe_bottom - margin))
    end_y=$((ly1 + margin))
    [ "$start_y" -gt "$end_y" ] || return 1
    printf '%s %s %s %s\n' "$x" "$start_y" "$x" "$end_y"
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

# Print the bounds ("x1 y1 x2 y2") of the only exact text/content-description
# node carrying $2. Duplicate entries, a missing label or malformed bounds print
# nothing, so a caller cannot silently pick one of two ambiguous dashboard rows.
ui_unique_label_bounds() (
    xml=$1
    label=$2
    [ -s "$xml" ] || return 0
    [ -n "$label" ] || return 0
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
                if ($0 !~ /<node[[:space:]]/) next
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (text != label && desc != label) next
                b = attr($0, "bounds")
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) next
                count++
                bounds = b
            }
            END {
                if (count == 1) emit(bounds)
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of the only clickable node representing the
# exact label/description $2. A directly clickable node wins; otherwise the
# nearest clickable ancestor is used. Two distinct clickable candidates, no
# candidate or a label with no clickable owner prints nothing, so an ambiguous
# settings entry is never tapped.
ui_unique_clickable_label_bounds() (
    xml=$1
    label=$2
    [ -s "$xml" ] || return 0
    [ -n "$label" ] || return 0
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
                if (b in seen) return
                seen[b] = 1
                order[++count] = b
            }
            function valid(b) {
                return b ~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/
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
                    stack[sp] = (clickable == "true" && valid(bounds)) ? bounds : ""
                }
                if (text != label && desc != label) next
                if (clickable == "true" && valid(bounds)) {
                    emit(bounds)
                    next
                }
                for (i = sp; i >= 1; i--) {
                    if (stack[i] != "") {
                        emit(stack[i])
                        break
                    }
                }
            }
            END {
                if (count == 1) {
                    s = order[1]
                    gsub(/\[/, " ", s)
                    gsub(/\]/, " ", s)
                    gsub(/,/, " ", s)
                    sub(/^[[:space:]]+/, "", s)
                    sub(/[[:space:]]+$/, "", s)
                    n = split(s, p, /[[:space:]]+/)
                    if (n == 4) print p[1], p[2], p[3], p[4]
                }
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of the topmost real slider. The class is the
# exact Compose/UIAutomator `android.widget.SeekBar`; a screen with no exposed
# SeekBar prints nothing so the caller fails closed instead of guessing a row or
# a thumb coordinate. Two sliders sharing the same top edge are ambiguous.
ui_top_slider_bounds() (
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
            function y1_of(b,    s, p, n) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return -1
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
                if (attr($0, "class") != "android.widget.SeekBar") next
                b = attr($0, "bounds")
                y = y1_of(b)
                if (y < 0) next
                if (best == "" || y < best_y) {
                    best = b
                    best_y = y
                    top_count = 1
                } else if (y == best_y) {
                    top_count++
                }
            }
            END {
                if (best == "" || top_count != 1) exit
                s = best
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n == 4) print p[1], p[2], p[3], p[4]
            }
        '
)

# Print the integer percentage associated with the measured top slider. The
# percentage must be a 50..150 multiple-of-10 text above/overlapping that exact
# slider and horizontally overlapping it. Exactly one distinct value is
# accepted; zero or several values print nothing so the caller never guesses.
ui_slider_percent() (
    xml=$1
    slider=$2
    [ -s "$xml" ] || return 0
    [ -n "$slider" ] || return 0
    set -- $slider
    [ "$#" -eq 4 ] || return 0
    want="[$1,$2][$3,$4]"
    sx1=$1
    sy1=$2
    sx2=$3
    sy2=$4
    tr '>' '\n' < "$xml" |
        awk -v want="$want" -v sx1="$sx1" -v sy1="$sy1" -v sx2="$sx2" -v sy2="$sy2" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function coords(b, out,    s, p, n) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return 0
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return 0
                out[1] = p[1] + 0
                out[2] = p[2] + 0
                out[3] = p[3] + 0
                out[4] = p[4] + 0
                return 1
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                b = attr($0, "bounds")
                if (attr($0, "class") == "android.widget.SeekBar" && b == want) {
                    target = 1
                }
                text = attr($0, "text")
                sub(/[[:space:]]+$/, "", text)
                if (text !~ /^[0-9][0-9]?[0-9]?%$/) next
                if (!coords(b, p)) next
                value = text
                sub(/%$/, "", value)
                value = value + 0
                if (value < 50 || value > 150 || value % 10 != 0) next
                if (p[2] < sy1 - 400) next
                if (p[4] > sy2) next
                if (p[3] <= sx1 || p[1] >= sx2) next
                seen[value] = 1
                vcount++
            }
            END {
                if (!target) exit
                if (vcount != 1) exit
                for (v in seen) print v
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of the only focused real SeekBar. No focused
# slider, a focused non-slider, malformed bounds or two focused sliders print
# nothing.
ui_focused_slider_bounds() (
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
            {
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "class") != "android.widget.SeekBar") next
                if (attr($0, "focused") != "true") next
                b = attr($0, "bounds")
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) next
                count++
                bounds = b
            }
            END {
                if (count != 1) exit
                s = bounds
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n == 4) print p[1], p[2], p[3], p[4]
            }
        '
)

# Print one "x1 y1 x2 y2" line per measured widget-host node on HOME. Matches
# only the inherited launcher host class or an explicit app-widget resource id,
# never an arbitrary large container. Missing hosts print nothing.
ui_widget_host_bounds() (
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
            {
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                cls = attr($0, "class")
                if (cls !~ /AppWidgetHostView$/ &&
                    rid !~ /(^|\/)(app_widget|widget_host|appwidget)$/) next
                b = attr($0, "bounds")
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) next
                s = b
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n == 4) print p[1], p[2], p[3], p[4]
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of the largest measured scrollable container
# on a settings screen, clipped to the safe viewport above the optional
# navigation-bar top. The settings screens use a Compose verticalScroll Column,
# so this reads the real `scrollable="true"` node rather than a guessed phone
# height or a hardcoded coordinate. Prints nothing when no scrollable container
# is measurable. When the content is already at its end, UiAutomator reports
# that same surface as `scrollable="false"`; use
# ui_known_scroll_container_bounds as a measured fallback there, never as a
# substitute for this strict true-scroll reading.
ui_scroll_container_bounds() (
    xml=$1
    nav_top=${2:-}
    [ -s "$xml" ] || return 0
    case "$nav_top" in '' | *[!0-9]*) nav_top= ;; esac
    values=$(tr '>' '\n' < "$xml" |
        awk '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function area(b,    s, p, n) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return -1
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                return (p[3] - p[1]) * (p[4] - p[2])
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "scrollable") != "true") next
                b = attr($0, "bounds")
                a = area(b)
                if (a > best_area) {
                    best_area = a
                    best = b
                }
            }
            END { if (best != "") print best }
        ')
    [ -n "$values" ] || return 0
    values=$(printf '%s\n' "$values" | tr '[],' '   ')
    set -- $values
    x1=$1
    y1=$2
    x2=$3
    y2=$4
    if [ -n "$nav_top" ] && [ "$nav_top" -gt 0 ] && [ "$y2" -gt "$nav_top" ]; then
        y2=$nav_top
    fi
    [ "$y2" -gt "$y1" ] || return 0
    printf '%s %s %s %s\n' "$x1" "$y1" "$x2" "$y2"
)

# Print the bounds ("x1 y1 x2 y2") of a measured container known to scroll even
# when it reports `scrollable="false"` because its content is already at the
# end. Only the exact `android.widget.ScrollView` class (what UiAutomator
# reports for a Compose `verticalScroll` surface) inside the expected app
# package, with a `scrollable="false"` flag and strictly positive measured
# bounds, is accepted. Arbitrary roots, decor/other views, wrong-package nodes
# and missing/zero-sized bounds are ignored. The result is clipped below the
# measured navigation-bar top exactly like the strict helper, so a partially
# clipped control still fails the visibility check. Prints nothing when no such
# container is measurable.
ui_known_scroll_container_bounds() (
    xml=$1
    nav_top=${2:-}
    package=${3:-}
    [ -s "$xml" ] || return 0
    [ -n "$package" ] || return 0
    case "$nav_top" in '' | *[!0-9]*) nav_top= ;; esac
    values=$(tr '>' '\n' < "$xml" |
        awk -v want_pkg="$package" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function area(b,    s, p, n, w, h) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return -1
                s = b
                gsub(/[^0-9]+/, " ", s)
                sub(/^ +/, "", s)
                sub(/ +$/, "", s)
                n = split(s, p, / +/)
                if (n != 4) return -1
                w = p[3] - p[1]
                h = p[4] - p[2]
                if (w <= 0 || h <= 0) return -1
                return w * h
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "class") != "android.widget.ScrollView") next
                if (attr($0, "package") != want_pkg) next
                if (attr($0, "scrollable") != "false") next
                b = attr($0, "bounds")
                a = area(b)
                if (a > best_area) {
                    best_area = a
                    best = b
                }
            }
            END { if (best != "") print best }
        ')
    [ -n "$values" ] || return 0
    values=$(printf '%s\n' "$values" | tr '[],' '   ')
    set -- $values
    x1=$1
    y1=$2
    x2=$3
    y2=$4
    if [ -n "$nav_top" ] && [ "$nav_top" -gt 0 ] && [ "$y2" -gt "$nav_top" ]; then
        y2=$nav_top
    fi
    [ "$y2" -gt "$y1" ] || return 0
    printf '%s %s %s %s\n' "$x1" "$y1" "$x2" "$y2"
)

# Print the clickable label's bounds only when the whole control is measured
# inside the supplied viewport. A control clipped by the viewport edge is not
# tappable evidence and prints nothing.
ui_clickable_label_within() (
    xml=$1
    label=$2
    viewport=$3
    [ -n "$viewport" ] || return 0
    bounds=$(ui_clickable_label_bounds "$xml" "$label")
    [ -n "$bounds" ] || return 0
    set -- $bounds
    [ "$#" -eq 4 ] || return 0
    bx1=$1
    by1=$2
    bx2=$3
    by2=$4
    set -- $viewport
    [ "$#" -eq 4 ] || return 0
    vx1=$1
    vy1=$2
    vx2=$3
    vy2=$4
    [ "$by2" -gt "$by1" ] || return 0
    if [ "$by1" -lt "$vy1" ] || [ "$by2" -gt "$vy2" ]; then
        return 0
    fi
    if [ "$bx1" -lt "$vx1" ] || [ "$bx2" -gt "$vx2" ]; then
        return 0
    fi
    printf '%s %s %s %s\n' "$bx1" "$by1" "$bx2" "$by2"
)

# Print "x y_from y_to" for a genuine vertical scroll inside the measured
# settings scroll container, clipped to the safe viewport. Prints nothing when
# the container or a usable band is unavailable so the caller fails closed.
settings_scroll_target() (
    xml=$1
    nav_top=${2:-}
    container=$(ui_scroll_container_bounds "$xml" "$nav_top")
    [ -n "$container" ] || return 1
    set -- $container
    x=$((($1 + $3) / 2))
    y1=$2
    y2=$4
    span=$((y2 - y1))
    [ "$span" -ge 200 ] || return 1
    y_from=$((y2 - span / 5))
    y_to=$((y1 + span / 5))
    [ "$y_from" -gt "$y_to" ] || return 1
    printf '%s %s %s\n' "$x" "$y_from" "$y_to"
)

# Print the bottom y of the workspace header search container above the measured
# dock. This is the smartspace/header band on the actual HOME; the empty central
# workspace starts below it. Prints nothing when no such container is exposed.
ui_header_bottom() (
    xml=$1
    dock_top=${2:-}
    [ -s "$xml" ] || return 0
    case "$dock_top" in '' | *[!0-9]*) return 0 ;; esac
    tr '>' '\n' < "$xml" |
        awk -v dock_top="$dock_top" '
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
                y2 = y_of(bounds, 4)
                if (y1 < dock_top && y2 > best) best = y2
            }
            END {
                if (best > 0) print best
            }
        '
)

# Succeed when the point ($2,$3) is not inside an occupied HOME node. A node is
# occupied when it is a labelled clickable item (app icon, folder, shortcut) or
# any real widget host, including PendingAppWidgetHostView. Widget hosts are
# occupied regardless of their clickable, text and content-desc flags because
# UIAutomator exposes a hosted widget as a non-clickable, often unlabelled node.
# The optional $4 clearance expands widget-host bounds so a long-press keeps a
# safe distance from the widget edge.
ui_point_is_free() (
    xml=$1
    px=$2
    py=$3
    clearance=${4:-0}
    [ -s "$xml" ] || return 1
    case "$px" in '' | *[!0-9]*) return 1 ;; esac
    case "$py" in '' | *[!0-9]*) return 1 ;; esac
    case "$clearance" in '' | *[!0-9]*) return 1 ;; esac
    occupied=$(tr '>' '\n' < "$xml" |
        awk -v px="$px" -v py="$py" -v clearance="$clearance" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function v_of(b, field,    s, n, p) {
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
                cls = attr($0, "class")
                rid = attr($0, "resource-id")
                is_host = (cls ~ /AppWidgetHostView$/) || (rid ~ /(^|\/)appwidget$/)
                clickable = attr($0, "clickable")
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                is_labelled_clickable = (clickable == "true" && (text != "" || desc != ""))
                if (!is_host && !is_labelled_clickable) next
                bounds = attr($0, "bounds")
                if (bounds == "") next
                x1 = v_of(bounds, 1)
                y1 = v_of(bounds, 2)
                x2 = v_of(bounds, 3)
                y2 = v_of(bounds, 4)
                if (is_host && clearance > 0) {
                    x1 -= clearance
                    y1 -= clearance
                    x2 += clearance
                    y2 += clearance
                }
                if (px >= x1 && px <= x2 && py >= y1 && py <= y2) {
                    print "occupied"
                    exit
                }
            }
        ')
    [ -z "$occupied" ]
)

# Compute a real long-press point in the empty central HOME workspace. The band
# is bounded by the measured header bottom and dock top, so it never lands on the
# header, dock icons or the bottom QSB. Candidate points walk away from the exact
# centre when a labelled clickable item or a widget host occupies it. The final
# candidates reach the empty band below a low widget such as the Device card, and
# widget-host edges keep one margin of clearance. Prints "x y".
home_longpress_target() (
    xml=$1
    root=$(ui_root_bounds "$xml")
    [ -n "$root" ] || return 1
    set -- $root
    rx1=$1
    ry1=$2
    rx2=$3
    ry2=$4
    width=$((rx2 - rx1))
    height=$((ry2 - ry1))
    [ "$width" -gt 0 ] && [ "$height" -gt 0 ] || return 1
    dock_top=$(ui_dock_top "$xml" "$root")
    [ -n "$dock_top" ] || dock_top=$((ry1 + height * 85 / 100))
    header_bottom=$(ui_header_bottom "$xml" "$dock_top")
    [ -n "$header_bottom" ] || header_bottom=$((ry1 + height * 15 / 100))
    margin=$((height * 4 / 100))
    band_top=$((header_bottom + margin))
    band_bottom=$((dock_top - margin))
    [ "$band_bottom" -gt "$band_top" ] || return 1
    x=$((rx1 + width / 2))
    band=$((band_bottom - band_top))
    for pct in 50 60 70 40 30 80 20 90 95 100; do
        y=$((band_top + band * pct / 100))
        if ui_point_is_free "$xml" "$x" "$y" "$margin"; then
            printf '%s %s\n' "$x" "$y"
            return 0
        fi
    done
    # Every measured candidate is occupied. Returning the band centre here would
    # long-press an app icon or widget and open an item-specific menu, so fail
    # instead of producing an unsafe fallback point.
    return 1
)

# Succeed only when the grid preview exposes a real workspace ViewGroup whose
# bounds sit above every slider and strictly inside the window root, with a
# hotseat/search container inside it. The inherited screen renders the preview
# as an AndroidViewHolder/ViewGroup, so the check is bounds-based and never
# depends on a LauncherPreviewView class name.
grid_preview_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
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
            function v_of(b, field,    s, n, p) {
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
                cls = attr($0, "class")
                rid = attr($0, "resource-id")
                bounds = attr($0, "bounds")
                if (root == "" && bounds != "") root = bounds
                if (preview == "" && rid ~ /(^|\/)workspace$/ && bounds != "") {
                    preview = bounds
                }
                if (cls == "android.widget.SeekBar" && bounds != "") {
                    top = v_of(bounds, 2)
                    if (control_top == "" || top < control_top) control_top = top
                }
                if (bounds != "" &&
                    rid ~ /(^|\/)(hotseat|search_container_workspace)$/) {
                    hot[++hot_count] = bounds
                }
            }
            END {
                if (root == "" || preview == "" || control_top == "") exit 1
                px1 = v_of(preview, 1); py1 = v_of(preview, 2)
                px2 = v_of(preview, 3); py2 = v_of(preview, 4)
                rx1 = v_of(root, 1); ry1 = v_of(root, 2)
                rx2 = v_of(root, 3); ry2 = v_of(root, 4)
                if (px1 < 0 || py1 < 0 || px2 <= px1 || py2 <= py1) exit 1
                if (px1 < rx1 || py1 < ry1 || px2 > rx2 || py2 > ry2) exit 1
                if (px2 - px1 >= rx2 - rx1) exit 1
                if (py2 - py1 >= ry2 - ry1) exit 1
                if (py2 >= control_top) exit 1
                inside = 0
                for (i = 1; i <= hot_count; i++) {
                    hx1 = v_of(hot[i], 1); hy1 = v_of(hot[i], 2)
                    hx2 = v_of(hot[i], 3); hy2 = v_of(hot[i], 4)
                    if (hx1 >= px1 && hy1 >= py1 && hx2 <= px2 && hy2 <= py2) {
                        inside = 1
                        break
                    }
                }
                exit (inside ? 0 : 1)
            }
        '
)

# Succeed only when the captured Home screen grid preferences expose the real
# preview, the Columns/Rows/Dock icons controls and Apply. The sliders must be
# actual accessibility SeekBar nodes, not merely the English labels.
grid_settings_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
    grep -Fq 'text="Home screen grid"' "$xml" || return 1
    for label in Columns Rows 'Dock icons' Apply; do
        grep -Fq "text=\"$label\"" "$xml" || return 1
    done
    sliders=$(grep -o 'class="android.widget.SeekBar"' "$xml" | wc -l | tr -d ' ')
    [ "$sliders" -ge 3 ] || return 1
    grid_preview_is_ready "$xml" || return 1
    return 0
)

# Succeed only when Apply is still the greyed, non-clickable control that the
# inherited screen renders. The label is a separate TextView and the disabled
# state is visual, so the accessibility enabled flag stays true; the reliable
# signal is that the label is not clickable and a non-clickable Button contains
# its bounds. A clickable Apply or a missing containing Button is rejected.
grid_apply_is_unchanged() (
    xml=$1
    [ -s "$xml" ] || return 1
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
            function v_of(b, field,    s, n, p) {
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
                text = attr($0, "text")
                cls = attr($0, "class")
                click = attr($0, "clickable")
                bounds = attr($0, "bounds")
                if (text == "Apply" && bounds != "" && apply == "") {
                    apply = bounds
                    apply_click = click
                }
                if (cls == "android.widget.Button" && bounds != "") {
                    btn[++btn_count] = bounds
                    btn_click[btn_count] = click
                }
            }
            END {
                if (apply == "") exit 1
                if (apply_click == "true") exit 1
                ax1 = v_of(apply, 1); ay1 = v_of(apply, 2)
                ax2 = v_of(apply, 3); ay2 = v_of(apply, 4)
                for (i = 1; i <= btn_count; i++) {
                    if (btn_click[i] == "true") continue
                    bx1 = v_of(btn[i], 1); by1 = v_of(btn[i], 2)
                    bx2 = v_of(btn[i], 3); by2 = v_of(btn[i], 4)
                    if (ax1 >= bx1 && ay1 >= by1 && ax2 <= bx2 && ay2 <= by2) {
                        exit 0
                    }
                }
                exit 1
            }
        '
)

# Succeed only when the real HOME long-press options popup is open. The actual
# hierarchy exposes pkg:id/popup_container with several clickable
# pkg:id/system_shortcut rows whose pkg:id/bubble_text labels include Widgets
# plus a home-level option. Class names are not reliable, so readiness comes
# from the real resource ids and the clickable shortcut rows; an item menu or a
# page that merely contains the word "Widgets" is rejected.
home_popup_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
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
            {
                if ($0 ~ /<\/node/) {
                    if (sp > 0) sp--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                click = attr($0, "clickable")
                text = attr($0, "text")
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                is_shortcut = (rid ~ /(^|\/)system_shortcut$/ && click == "true")
                inside = is_shortcut
                for (i = 1; i <= sp && !inside; i++) {
                    if (stack[i] == 1) inside = 1
                }
                if (rid ~ /(^|\/)popup_container$/) has_container = 1
                if (is_shortcut) shortcuts++
                if (inside && text == "Widgets") has_widgets = 1
                if (inside && (text == "Home settings" || text == "Wallpapers")) {
                    has_home_option = 1
                }
                if (!selfclose) {
                    sp++
                    stack[sp] = is_shortcut ? 1 : 0
                }
            }
            END {
                exit !(has_container && shortcuts >= 2 && has_widgets && has_home_option)
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of a clickable widgets_list_header whose
# app_title matches $2 and whose app_subtitle reports at least one real widget.
# A shortcut-only header ("1 shortcut") is never selected, and no class name is
# assumed. The subtitle is locale text, so only the positive widget count is
# required.
widget_picker_provider_bounds() (
    xml=$1
    want=$2
    [ -s "$xml" ] || return 0
    [ -n "$want" ] || return 0
    tr '>' '\n' < "$xml" |
        awk -v want="$want" '
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
                rid = attr($0, "resource-id")
                click = attr($0, "clickable")
                bounds = attr($0, "bounds")
                text = attr($0, "text")
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                is_header = (rid ~ /(^|\/)widgets_list_header$/ &&
                    click == "true" && bounds != "")
                if (!selfclose) {
                    sp++
                    header_idx[sp] = 0
                }
                if (is_header) {
                    hcount++
                    header_bounds[hcount] = bounds
                    header_title[hcount] = ""
                    header_sub[hcount] = ""
                    if (!selfclose) header_idx[sp] = hcount
                }
                hd = 0
                for (i = sp; i >= 1; i--) {
                    if (header_idx[i] > 0) {
                        hd = header_idx[i]
                        break
                    }
                }
                if (hd > 0) {
                    if (rid ~ /(^|\/)app_title$/) header_title[hd] = text
                    if (rid ~ /(^|\/)app_subtitle$/) header_sub[hd] = text
                }
            }
            END {
                for (i = 1; i <= hcount; i++) {
                    if (header_title[i] != want) continue
                    if (header_sub[i] ~ /(^|[^0-9])[1-9][0-9]*[[:space:]]+widgets?/) {
                        emit(header_bounds[i])
                        exit
                    }
                }
            }
        '
)

# Print the bounds of the widget_preview_container below the selected provider
# header and above the next provider header. The container must be clickable or
# long-clickable, matching the inherited WidgetCell preview. A preview from a
# collapsed or unrelated provider is rejected.
widget_picker_preview_bounds() (
    xml=$1
    header=$2
    [ -s "$xml" ] || return 0
    set -- $header
    [ "$#" -eq 4 ] || return 0
    hy2=$4
    tr '>' '\n' < "$xml" |
        awk -v hy2="$hy2" '
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
            function emit(b,    s, p, n) {
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
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                bounds = attr($0, "bounds")
                if (bounds !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) next
                y1 = y_of(bounds, 2)
                if (rid ~ /(^|\/)widgets_list_header$/ && y1 > hy2) {
                    if (next_top == "" || y1 < next_top) next_top = y1
                }
                if (rid !~ /(^|\/)widget_preview_container$/) next
                if (attr($0, "clickable") != "true" &&
                    attr($0, "long-clickable") != "true") next
                if (y1 <= hy2) next
                if (next_top != "" && y1 >= next_top) next
                if (best == "" || y1 < best_y) {
                    best = bounds
                    best_y = y1
                }
            }
            END {
                if (best != "") emit(best)
            }
        '
)

# Print the selected preview widget's own caption from the same actual
# WidgetCell that contains the measured widget_preview_container bounds. The
# picker can show several widget cells for one provider at the same vertical
# position (CI161: "Analog clock" and "Digital clock" under the Clock header),
# so neither the provider header nor the first global widget_name is the
# consent identity. The caption is printed only when exactly one WidgetCell
# owns the selected preview and that cell exposes exactly one non-empty
# widget_name text. Missing, foreign or ambiguous captions print nothing so the
# caller can fail closed.
widget_picker_selected_caption() (
    xml=$1
    preview=$2
    [ -s "$xml" ] || return 0
    set -- $preview
    [ "$#" -eq 4 ] || return 0
    want="[$1,$2][$3,$4]"
    tr '>' '\n' < "$xml" |
        awk -v want="$want" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            {
                if ($0 ~ /<\/node/) {
                    if (sp > 0) sp--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                cls = attr($0, "class")
                bounds = attr($0, "bounds")
                text = attr($0, "text")
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                cell = (sp > 0 ? stack_cell[sp] : 0)
                if (cls ~ /(^|\.)WidgetCell$/ && !selfclose) {
                    cell_count++
                    cell = cell_count
                }
                if (cell > 0) {
                    if (rid ~ /(^|\/)widget_preview_container$/ &&
                        bounds == want) {
                        cell_preview[cell]++
                    }
                    if (rid ~ /(^|\/)widget_name$/ && text != "") {
                        cell_captions[cell]++
                        cell_caption[cell] = text
                    }
                }
                if (!selfclose) {
                    sp++
                    stack_cell[sp] = cell
                }
            }
            END {
                matched = 0
                for (i = 1; i <= cell_count; i++) {
                    if (cell_preview[i] > 0) {
                        matched++
                        selected = i
                    }
                }
                if (matched != 1) exit
                if (cell_captions[selected] != 1) exit
                print cell_caption[selected]
            }
        '
)

# Print the bounds ("x1 y1 x2 y2") of the widget picker search bar. The real
# inherited picker exposes widgets_search_bar_edit_text; the outer
# search_bar_container/widgets_search_bar is the fallback so the viewport still
# has a measured top edge. No class name or English placeholder is assumed.
widget_picker_search_bar_bounds() (
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
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                b = attr($0, "bounds")
                if (rid ~ /(^|\/)widgets_search_bar_edit_text$/ && input_b == "")
                    input_b = b
                if (rid ~ /(^|\/)(search_bar_container|widgets_search_bar)$/ && outer_b == "")
                    outer_b = b
            }
            END {
                if (input_b != "") emit(input_b)
                else if (outer_b != "") emit(outer_b)
            }
        '
)

# Print the usable widget-preview viewport ("x1 y1 x2 y2"): inside the root,
# below the search bar and 100 px above the root bottom. The bottom margin keeps
# a preview off the navigation bar; the root is the real UIAutomator window
# bounds, never a fixed display size. Prints nothing when either edge is
# unavailable.
widget_picker_viewport_bounds() (
    xml=$1
    [ -s "$xml" ] || return 0
    root=$(ui_root_bounds "$xml")
    [ -n "$root" ] || return 0
    search=$(widget_picker_search_bar_bounds "$xml")
    [ -n "$search" ] || return 0
    set -- $root
    rx1=$1
    ry1=$2
    rx2=$3
    ry2=$4
    set -- $search
    top=$4
    if [ "$top" -lt "$ry1" ]; then
        top=$ry1
    fi
    bottom=$((ry2 - 100))
    if [ "$bottom" -le "$top" ]; then
        return 0
    fi
    printf '%s %s %s %s\n' "$rx1" "$top" "$rx2" "$bottom"
)

# Succeed only when a preview is fully inside the measured viewport and at least
# 100 px tall. A 51 px preview clipped by the navigation bar is rejected even
# when its resource id is valid.
widget_picker_preview_is_visible() (
    preview=$1
    viewport=$2
    if [ -z "$preview" ] || [ -z "$viewport" ]; then
        return 1
    fi
    set -- $preview
    if [ "$#" -ne 4 ]; then
        return 1
    fi
    px1=$1
    py1=$2
    px2=$3
    py2=$4
    set -- $viewport
    if [ "$#" -ne 4 ]; then
        return 1
    fi
    vx1=$1
    vy1=$2
    vx2=$3
    vy2=$4
    if [ "$py2" -le "$py1" ]; then
        return 1
    fi
    if [ "$((py2 - py1))" -lt 100 ]; then
        return 1
    fi
    if [ "$py1" -lt "$vy1" ]; then
        return 1
    fi
    if [ "$py2" -ge "$vy2" ]; then
        return 1
    fi
    if [ "$px1" -lt "$vx1" ]; then
        return 1
    fi
    if [ "$px2" -gt "$vx2" ]; then
        return 1
    fi
    return 0
)

# Print the bounds of the measured widget list (inherited primary/search list or
# the Compose catalog) used for a bounded genuine scroll.
widget_picker_list_bounds() (
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
                if ($0 !~ /<node[[:space:]]/) next
                if (best != "") next
                rid = attr($0, "resource-id")
                if (rid ~ /(^|\/)(primary_widgets_list_view|search_widgets_list_view|widgets_catalog)$/)
                    best = attr($0, "bounds")
            }
            END { if (best != "") emit(best) }
        '
)

# Print "x y_from y_to" for a genuine vertical scroll inside the measured widget
# list, clamped to the usable viewport so the gesture never lands on the
# navigation bar. Prints nothing when the list or viewport is unavailable.
widget_picker_scroll_target() (
    xml=$1
    list=$(widget_picker_list_bounds "$xml")
    viewport=$(widget_picker_viewport_bounds "$xml")
    if [ -z "$list" ] || [ -z "$viewport" ]; then
        return 1
    fi
    set -- $list
    lx1=$1
    ly1=$2
    lx2=$3
    ly2=$4
    set -- $viewport
    vx1=$1
    vy1=$2
    vx2=$3
    vy2=$4
    x=$(((lx1 + lx2) / 2))
    top=$ly1
    if [ "$top" -lt "$vy1" ]; then
        top=$vy1
    fi
    bottom=$ly2
    if [ "$bottom" -gt "$vy2" ]; then
        bottom=$vy2
    fi
    if [ "$bottom" -le "$top" ]; then
        return 1
    fi
    span=$((bottom - top))
    if [ "$span" -lt 200 ]; then
        return 1
    fi
    y_from=$((bottom - span / 5))
    y_to=$((top + span / 5))
    if [ "$y_from" -le "$y_to" ]; then
        return 1
    fi
    printf '%s %s %s\n' "$x" "$y_from" "$y_to"
)

# Print the bounds of the exposed widget Add button by its real resource id.
# The button may be icon-only, so English text is not required. It must be
# enabled as well as clickable, so a disabled overlay is never tapped.
widget_picker_add_button_bounds() (
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
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "resource-id") !~ /(^|\/)widget_add_button$/) next
                if (attr($0, "clickable") != "true") next
                if (attr($0, "enabled") != "true") next
                emit(attr($0, "bounds"))
                exit
            }
        '
)

# Print the safe intersection ("x1 y1 x2 y2") of an exposed Add button and the
# measured picker viewport, pulled 32 px above the viewport's bottom edge so the
# tap can never land on the navigation bar. CI120 exposed Add at
# [434,1755][645,1881] while the navigation bar begins around 1800; the original
# centre 1818 was unsafe. A result is printed only when the remaining box is at
# least 24 px in both dimensions, so a clipped or fully hidden Add is rejected
# instead of being tapped at its unsafe original centre. Prints nothing when
# there is no large-enough safe intersection.
widget_add_safe_bounds() (
    add=$1
    viewport=$2
    [ -n "$add" ] || return 0
    [ -n "$viewport" ] || return 0
    set -- $add
    [ "$#" -eq 4 ] || return 0
    ax1=$1
    ay1=$2
    ax2=$3
    ay2=$4
    set -- $viewport
    [ "$#" -eq 4 ] || return 0
    vx1=$1
    vy1=$2
    vx2=$3
    vy2=$4
    x1=$ax1
    if [ "$vx1" -gt "$x1" ]; then
        x1=$vx1
    fi
    y1=$ay1
    if [ "$vy1" -gt "$y1" ]; then
        y1=$vy1
    fi
    x2=$ax2
    if [ "$vx2" -lt "$x2" ]; then
        x2=$vx2
    fi
    y2=$ay2
    if [ "$vy2" -lt "$y2" ]; then
        y2=$vy2
    fi
    y2=$((y2 - 32))
    if [ "$x2" -le "$x1" ] || [ "$y2" -le "$y1" ]; then
        return 0
    fi
    if [ "$((x2 - x1))" -lt 24 ] || [ "$((y2 - y1))" -lt 24 ]; then
        return 0
    fi
    printf '%s %s %s %s\n' "$x1" "$y1" "$x2" "$y2"
)

# Succeed only for the real Android widget-bind consent dialog
# (AllowBindAppWidgetActivity). The alertTitle must be the exact title, the
# android:id/message must name this launcher and the selected widget, and the
# android:id/button1 control must be an enabled, clickable Create button owned by
# com.android.settings. Button labels are matched case-insensitively because the
# platform renders them as CREATE/CANCEL. A generic dialog with a Create button
# or unrelated text elsewhere in the tree is not accepted.
widget_bind_consent_is_ready() (
    xml=$1
    launcher=$2
    widget=$3
    [ -s "$xml" ] || return 1
    [ -n "$launcher" ] || return 1
    [ -n "$widget" ] || return 1
    tr '>' '\n' < "$xml" |
        awk -v launcher="$launcher" -v widget="$widget" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            {
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "package") != "com.android.settings") next
                rid = attr($0, "resource-id")
                if (rid == "android:id/alertTitle") {
                    if (tolower(attr($0, "text")) == "create widget and allow access?") title = 1
                } else if (rid == "android:id/message") {
                    msg = tolower(attr($0, "text"))
                    if (index(msg, "application: " tolower(launcher)) > 0 &&
                        index(msg, "widget: " tolower(widget)) > 0) message = 1
                } else if (rid == "android:id/button1") {
                    if (attr($0, "clickable") == "true" &&
                        attr($0, "enabled") == "true" &&
                        tolower(attr($0, "text")) == "create") button = 1
                } else if (rid == "android:id/alwaysUse") {
                    always = 1
                }
            }
            END { exit !(title && message && button && always) }
        '
)

# Print the measured bounds of the consent dialog's Create control by its
# android:id/button1 resource id. The dialog must still carry the exact title,
# the com.android.settings package, the launcher/widget message identity and an
# enabled, clickable button whose label may be CREATE or Create. Handles compact
# single-line dumps.
widget_bind_create_button_bounds() (
    xml=$1
    launcher=${2:-}
    widget=${3:-}
    [ -s "$xml" ] || return 0
    [ -n "$launcher" ] || return 0
    [ -n "$widget" ] || return 0
    tr '>' '\n' < "$xml" |
        awk -v launcher="$launcher" -v widget="$widget" '
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
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "package") != "com.android.settings") next
                rid = attr($0, "resource-id")
                if (rid == "android:id/alertTitle") {
                    if (tolower(attr($0, "text")) == "create widget and allow access?") title = 1
                } else if (rid == "android:id/message") {
                    msg = tolower(attr($0, "text"))
                    if (index(msg, "application: " tolower(launcher)) > 0 &&
                        index(msg, "widget: " tolower(widget)) > 0) message = 1
                } else if (rid == "android:id/button1") {
                    if (attr($0, "clickable") == "true" &&
                        attr($0, "enabled") == "true" &&
                        tolower(attr($0, "text")) == "create") bounds = attr($0, "bounds")
                }
            }
            END {
                if (!(title && message)) exit 1
                emit(bounds)
            }
        '
)

# Succeed when the consent dialog's Always allow checkbox is checked. The flow
# refuses to tap Create in that state so a smoke run never grants permanent
# widget-binding permission.
widget_bind_always_allow_is_checked() (
    xml=$1
    [ -s "$xml" ] || return 1
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
            {
                if ($0 !~ /<node[[:space:]]/) next
                if (attr($0, "resource-id") != "android:id/alwaysUse") next
                if (attr($0, "checked") == "true") found = 1
            }
            END { exit !found }
        '
)

# Print the bounds of a new AppWidgetHostView in the workspace, comparing the
# current hierarchy with the pre-widget HOME. Both hierarchies are normalised to
# one node record per line (UIAutomator can emit the whole tree on a single
# line), and explicit R/C markers keep the reference distinct even when it is
# empty. A host inside a widget-picker preview or sheet is never accepted; when
# the hierarchy exposes a workspace, only a host inside that workspace counts.
#
# $3 is an optional expected provider label (the picker-selected app title). It
# is matched against the host content-desc so a new Calendar is not confused
# with an existing own Clock at the same geometry: reference hosts with another
# label are ignored, pending hosts are never accepted, and the result must be a
# real host inside a visible workspace. Without $3 the previous first-unseen
# behaviour is preserved.
home_widget_bounds() (
    xml=$1
    reference=${2:-}
    expected=${3:-}
    [ -s "$xml" ] || return 0
    {
        if [ -n "$reference" ] && [ -s "$reference" ]; then
            tr '>' '\n' < "$reference" |
                awk '{ print "R\t" $0 }'
        fi
        tr '>' '\n' < "$xml" |
            awk '{ print "C\t" $0 }'
    } |
        awk -F '\t' -v expected="$expected" '
            function attr(s, name,    pat, v) {
                pat = "[[:space:]]" name "=\"[^\"]*\""
                if (!match(s, pat)) return ""
                v = substr(s, RSTART, RLENGTH)
                sub("^[[:space:]]" name "=\"", "", v)
                sub("\"$", "", v)
                return v
            }
            function emit(b,    s, p, n) {
                s = b
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n == 4) print p[1], p[2], p[3], p[4]
            }
            function is_workspace(rid, cls) {
                return rid ~ /(^|\/)workspace(_right|_grid)?$/ ||
                    cls ~ /(^|\.)Workspace$/
            }
            function is_preview(rid, cls) {
                return rid ~ /(^|\/)(widget_preview_container|widgets_list_header|widgets_catalog|widgets_search_bar|primary_widgets_list_view)$/ ||
                    cls ~ /(WidgetCell|WidgetCellPreview|WidgetsListHeader|WidgetsBottomSheet|BaseWidgetSheet|AddItemWidgetsBottomSheet)/
            }
            function is_pending(cls) {
                return cls ~ /PendingAppWidgetHostView/
            }
            {
                kind = $1
                rec = substr($0, index($0, "\t") + 1)
                if (kind != last_kind) {
                    sp = 0
                    last_kind = kind
                }
                if (rec ~ /<\/node/) {
                    if (sp > 0) sp--
                    next
                }
                if (rec !~ /<node[[:space:]]/) next
                rid = attr(rec, "resource-id")
                cls = attr(rec, "class")
                bounds = attr(rec, "bounds")
                label = attr(rec, "content-desc")
                selfclose = (rec ~ /\/[[:space:]]*$/)
                parent_ws = (sp > 0 ? stack_ws[sp] : 0)
                parent_preview = (sp > 0 ? stack_preview[sp] : 0)
                ws = parent_ws || is_workspace(rid, cls)
                preview = parent_preview || is_preview(rid, cls)
                if (kind == "C" && ws) cur_saw_ws = 1
                if (cls ~ /AppWidgetHostView/ &&
                    bounds ~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) {
                    label_ok = (expected == "" || label == expected)
                    if (kind == "R") {
                        if (!preview && !is_pending(cls) && label_ok) seen[bounds] = 1
                    } else if (!preview && !is_pending(cls) && label_ok) {
                        # Select the first eligible unseen host while scanning.
                        # The reference is fully processed before the current
                        # tree, so `seen` is complete here. Previously the first
                        # current workspace host was recorded and then rejected
                        # if it was pre-existing, so a later new host (the added
                        # Calendar) was never examined.
                        if (expected != "") {
                            # Identity mode: only a real host inside a visible
                            # workspace counts. There is no outside-workspace
                            # fallback here.
                            if (ws && !(bounds in seen) && chosen_ws == "") {
                                chosen_ws = bounds
                            }
                        } else if (ws) {
                            if (!(bounds in seen) && chosen_ws == "") chosen_ws = bounds
                        } else if (!(bounds in seen) && chosen_nonws == "") {
                            chosen_nonws = bounds
                        }
                    }
                }
                if (!selfclose) {
                    sp++
                    stack_ws[sp] = ws
                    stack_preview[sp] = preview
                }
            }
            END {
                if (chosen_ws != "") emit(chosen_ws)
                else if (expected == "" && !cur_saw_ws && chosen_nonws != "") {
                    emit(chosen_nonws)
                }
            }
        '
)

# Succeed only when a placed widget's bounds sit inside the workspace that is
# actually visible on the page it was found on and do not overlap a launcher
# header or the dock that is actually present there. The first-page header is
# never inherited: a genuine later page may expose no
# search_container_workspace header, so its upper workspace is valid. Missing or
# malformed workspace/dock geometry fails closed rather than inventing a band.
# The labelled-row ui_dock_top is deliberately not used here because on a later
# page ordinary app icons can make it report a row above the real hotseat.
home_widget_page_geometry_ok() (
    xml=$1
    widget_bounds=$2
    [ -s "$xml" ] || return 1
    set -- $widget_bounds
    [ "$#" -eq 4 ] || return 1
    for field in "$@"; do
        case "$field" in '' | *[!0-9]*) return 1 ;; esac
    done
    bx1=$1
    by1=$2
    bx2=$3
    by2=$4
    [ "$bx1" -lt "$bx2" ] && [ "$by1" -lt "$by2" ] || return 1

    ws_bounds=$(ui_node_attribute "$xml" workspace bounds)
    [ -n "$ws_bounds" ] || ws_bounds=$(ui_node_attribute "$xml" workspace_right bounds)
    [ -n "$ws_bounds" ] || ws_bounds=$(ui_node_attribute "$xml" workspace_grid bounds)
    ws=$(ui_bounds_values "$ws_bounds")
    [ -n "$ws" ] || return 1
    set -- $ws
    ws_x1=$1
    ws_y1=$2
    ws_x2=$3
    ws_y2=$4
    [ "$ws_x1" -lt "$ws_x2" ] && [ "$ws_y1" -lt "$ws_y2" ] || return 1

    dock=$(ui_bounds_values "$(ui_node_attribute "$xml" hotseat bounds)")
    [ -n "$dock" ] || return 1
    set -- $dock
    dock_top=$2
    [ "$dock_top" -gt "$ws_y1" ] || return 1

    header_bottom=$(ui_header_bottom "$xml" "$dock_top")

    [ "$bx1" -ge "$ws_x1" ] || return 1
    [ "$by1" -ge "$ws_y1" ] || return 1
    [ "$bx2" -le "$ws_x2" ] || return 1
    [ "$by2" -le "$ws_y2" ] || return 1
    if [ -n "$header_bottom" ]; then
        [ "$by1" -ge "$header_bottom" ] || return 1
    fi
    [ "$by2" -le "$dock_top" ] || return 1
    return 0
)

# Succeed only when $xml still yields the exact selected provider host at
# $placed_bounds and that host's geometry is valid on the actual page. This keeps
# absent, foreign and picker-preview hosts from satisfying the check and then
# applies the page-local workspace/header/dock bounds.
placed_widget_page_is_safe() (
    xml=$1
    reference=${2:-}
    expected=${3:-}
    placed_bounds=${4:-}
    [ -n "$expected" ] || return 1
    [ -n "$placed_bounds" ] || return 1
    actual=$(home_widget_bounds "$xml" "$reference" "$expected")
    [ "$actual" = "$placed_bounds" ] || return 1
    home_widget_page_geometry_ok "$xml" "$placed_bounds"
)

# Print "<x1> <y> <x2> <y>" for a bounded horizontal workspace page swipe in the
# safe band between the actual workspace/header top and the actual hotseat. $2 is
# "next" or "prev". A genuine later page may expose no launcher
# search_container_workspace header, so its measured workspace upper bound is
# used; a real header is still protected. Missing, malformed or degenerate
# workspace/hotseat geometry and an impossible band fail closed. The labelled-row
# ui_dock_top is deliberately not used: ordinary app icons on a later page can
# report a row above the real hotseat.
workspace_page_swipe() (
    xml=$1
    direction=$2
    case "$direction" in
        next | prev) ;;
        *) return 1 ;;
    esac
    [ -s "$xml" ] || return 0

    ws_bounds=$(ui_node_attribute "$xml" workspace bounds)
    [ -n "$ws_bounds" ] || ws_bounds=$(ui_node_attribute "$xml" workspace_right bounds)
    [ -n "$ws_bounds" ] || ws_bounds=$(ui_node_attribute "$xml" workspace_grid bounds)
    ws=$(ui_bounds_values "$ws_bounds")
    [ -n "$ws" ] || return 0
    set -- $ws
    ws_x1=$1
    ws_y1=$2
    ws_x2=$3
    ws_y2=$4
    [ "$ws_x1" -lt "$ws_x2" ] && [ "$ws_y1" -lt "$ws_y2" ] || return 0

    dock=$(ui_bounds_values "$(ui_node_attribute "$xml" hotseat bounds)")
    [ -n "$dock" ] || return 0
    set -- $dock
    dock_x1=$1
    dock_y1=$2
    dock_x2=$3
    dock_y2=$4
    [ "$dock_x1" -lt "$dock_x2" ] && [ "$dock_y1" -lt "$dock_y2" ] || return 0
    [ "$dock_y1" -gt "$ws_y1" ] || return 0

    band_top=$ws_y1
    header_bottom=$(ui_header_bottom "$xml" "$dock_y1")
    if [ -n "$header_bottom" ]; then
        case "$header_bottom" in '' | *[!0-9]*) return 0 ;; esac
        [ "$header_bottom" -gt "$band_top" ] && band_top=$header_bottom
    fi
    [ "$band_top" -lt "$dock_y1" ] || return 0
    y=$((band_top + (dock_y1 - band_top) / 2))
    [ "$y" -ge "$ws_y1" ] && [ "$y" -le "$ws_y2" ] || return 0

    ws_width=$((ws_x2 - ws_x1))
    margin=$((ws_width / 5))
    [ "$margin" -ge 40 ] || margin=40
    left=$((ws_x1 + margin))
    right=$((ws_x2 - margin))
    [ "$left" -lt "$right" ] || return 0
    [ "$left" -gt "$ws_x1" ] && [ "$right" -lt "$ws_x2" ] || return 0

    case "$direction" in
        next) printf '%s %s %s %s\n' "$right" "$y" "$left" "$y" ;;
        prev) printf '%s %s %s %s\n' "$left" "$y" "$right" "$y" ;;
    esac
)

# Print the bounds ("x1 y1 x2 y2") of every visible pending AppWidgetHostView
# in the workspace, ordered left-to-right. A pending widget is the launcher's
# click-to-setup placeholder after the platform denied an automatic bind; it is
# never counted as a completed widget. Hosts inside the widget picker, a preview
# cell or a bottom sheet are rejected. When the hierarchy exposes a workspace,
# only pending hosts inside it are returned; the no-workspace fallback mirrors
# home_widget_bounds so a minimal hierarchy can still be exercised.
home_pending_widget_bounds() (
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
            function read_bounds(b,    s, p, n) {
                if (b !~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) return 0
                s = b
                gsub(/\[/, " ", s)
                gsub(/\]/, " ", s)
                gsub(/,/, " ", s)
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                n = split(s, p, /[[:space:]]+/)
                if (n != 4) return 0
                bx1 = p[1]
                by1 = p[2]
                bx2 = p[3]
                by2 = p[4]
                return 1
            }
            function is_workspace(rid, cls) {
                return rid ~ /(^|\/)workspace(_right|_grid)?$/ ||
                    cls ~ /(^|\.)Workspace$/
            }
            function is_preview(rid, cls) {
                return rid ~ /(^|\/)(widget_preview_container|widgets_list_header|widgets_catalog|widgets_search_bar|primary_widgets_list_view)$/ ||
                    cls ~ /(WidgetCell|WidgetCellPreview|WidgetsListHeader|WidgetsBottomSheet|BaseWidgetSheet|AddItemWidgetsBottomSheet)/
            }
            function sort_emit(n, keys, vals,    i, j, tk, tv) {
                for (i = 2; i <= n; i++) {
                    tk = keys[i] + 0
                    tv = vals[i]
                    j = i - 1
                    while (j >= 1 && (keys[j] + 0) > tk) {
                        keys[j + 1] = keys[j]
                        vals[j + 1] = vals[j]
                        j--
                    }
                    keys[j + 1] = tk
                    vals[j + 1] = tv
                }
                for (i = 1; i <= n; i++) print vals[i]
            }
            {
                if ($0 ~ /<\/node/) {
                    if (sp > 0) sp--
                    next
                }
                if ($0 !~ /<node[[:space:]]/) next
                rid = attr($0, "resource-id")
                cls = attr($0, "class")
                bounds = attr($0, "bounds")
                selfclose = ($0 ~ /\/[[:space:]]*$/)
                parent_ws = (sp > 0 ? stack_ws[sp] : 0)
                parent_preview = (sp > 0 ? stack_preview[sp] : 0)
                ws = parent_ws || is_workspace(rid, cls)
                preview = parent_preview || is_preview(rid, cls)
                if (ws) saw_ws = 1
                if (cls ~ /PendingAppWidgetHostView/ && read_bounds(bounds) && !preview) {
                    if (ws) {
                        n_ws++
                        ws_key[n_ws] = bx1
                        ws_val[n_ws] = bx1 " " by1 " " bx2 " " by2
                    } else {
                        n_non++
                        non_key[n_non] = bx1
                        non_val[n_non] = bx1 " " by1 " " bx2 " " by2
                    }
                }
                if (!selfclose) {
                    sp++
                    stack_ws[sp] = ws
                    stack_preview[sp] = preview
                }
            }
            END {
                if (saw_ws) sort_emit(n_ws, ws_key, ws_val)
                else sort_emit(n_non, non_key, non_val)
            }
        '
)


# Print providers of widget instances that are newly bound between two
# `dumpsys appwidget` captures. Each provider must sit inside a widget-id block
# (`AppWidgetId=N` on older dumps or `[N] id=N` on current Android), so an
# installed-provider list or a provider mentioned elsewhere cannot be mistaken
# for a newly bound widget. A new AppWidgetId is required even when the same
# provider was already installed.
#
# When $3 is set, the new widget's host package must equal it. Current Android
# prints the host in the widget block as `host=HostId{..., pkg:<package>}`; a
# `hostPackage=<package>` line is also accepted. If ownership cannot be proven,
# the helper prints nothing and the smoke fails closed. When $4 is `id`, each
# line is `<AppWidgetId><TAB><provider>` instead of just the provider.
appwidget_new_providers() (
    before=$1
    after=$2
    want_host=${3:-}
    with_id=${4:-}
    [ -s "$after" ] || return 0
    {
        if [ -n "$before" ] && [ -s "$before" ]; then
            awk '{ print "B\t" $0 }' "$before"
        fi
        awk '{ print "A\t" $0 }' "$after"
    } |
        awk -F '\t' -v want_host="$want_host" '
            function flush() {
                if (kind != "" && id != "" && provider != "" &&
                    (want_host == "" || host == want_host))
                    print kind "\t" id "\t" provider "\t" host
                id = ""
                provider = ""
                host = ""
            }
            function provider_of(line,    wrapped) {
                if (match(line, /provider=ComponentInfo\{[^}]*\}/))
                    return substr(line, RSTART, RLENGTH)
                if (match(line, /provider=ProviderId\{[^}]*ComponentInfo\{[^}]*\}/)) {
                    wrapped = substr(line, RSTART, RLENGTH)
                    if (match(wrapped, /ComponentInfo\{[^}]*\}/))
                        return "provider=" substr(wrapped, RSTART, RLENGTH)
                }
                return ""
            }
            {
                if ($1 != kind) {
                    flush()
                    kind = $1
                }
                line = substr($0, index($0, "\t") + 1)
                if (line ~ /^[[:space:]]*[A-Za-z][A-Za-z ]*:[[:space:]]*$/) {
                    flush()
                    next
                }
                if (line ~ /^[[:space:]]*\[[0-9]+\][[:space:]]+id=[0-9]+[[:space:]]*$/) {
                    flush()
                    id = line
                    sub(/^.*id=/, "", id)
                    sub(/[^0-9].*$/, "", id)
                    next
                }
                if (match(line, /AppWidgetId=[0-9]+/)) {
                    flush()
                    id = substr(line, RSTART, RLENGTH)
                    sub(/^AppWidgetId=/, "", id)
                    next
                }
                if (id == "") next
                p = provider_of(line)
                if (p != "") {
                    if (provider != "") flush()
                    if (id == "") next
                    provider = p
                }
                if (match(line, /host=HostId\{[^}]*\}/)) {
                    h = substr(line, RSTART, RLENGTH)
                    if (match(h, /pkg:[^},]*/)) {
                        host = substr(h, RSTART + 4, RLENGTH - 4)
                    }
                } else if (match(line, /hostPackage=[^[:space:]]+/)) {
                    host = substr(line, RSTART + 12, RLENGTH - 12)
                }
            }
            END { flush() }
        ' |
        awk -F '\t' -v with_id="$with_id" '
            $1 == "B" {
                seen[$2] = 1
                next
            }
            $1 == "A" {
                if (!($2 in seen) && !($2 in printed)) {
                    if (with_id == "id") {
                        print $2 "\t" $3
                    } else {
                        print $3
                    }
                    printed[$2] = 1
                }
            }
        '
)

# Print "<numeric AppWidgetId><TAB><provider class>" only when exactly one widget
# was newly bound between the two dumps, its host and provider package are both
# the running package, and its provider class is exactly one of the three DotWel
# providers. Zero records, multiple or mixed records, a non-numeric id, a foreign
# package and class prefix/suffix lookalikes all print nothing and fail closed.
own_widget_new_binding() (
    before=$1
    after=$2
    pkg=$3
    [ -s "$after" ] || return 0
    [ -n "$pkg" ] || return 0
    appwidget_new_providers "$before" "$after" "$pkg" id |
        awk -F '\t' -v pkg="$pkg" '
            function provider_class(provider,    info, parts) {
                if (provider !~ /^provider=ComponentInfo\{[^}]*\}$/) return ""
                info = provider
                sub(/^provider=ComponentInfo\{/, "", info)
                sub(/\}$/, "", info)
                if (split(info, parts, "/") != 2) return ""
                if (parts[1] != pkg) return ""
                return parts[2]
            }
            {
                count++
                if (NF != 2) {
                    bad = 1
                    next
                }
                if ($1 !~ /^[0-9]+$/) {
                    bad = 1
                    next
                }
                class = provider_class($2)
                if (class != "app.dotwel.widgets.DotWelClockWidgetProvider" &&
                    class != "app.dotwel.widgets.DotWelBatteryWidgetProvider" &&
                    class != "app.dotwel.widgets.DotWelDeviceWidgetProvider") {
                    bad = 1
                    next
                }
                id = $1
                bound = class
            }
            END {
                if (bad || count != 1) exit 0
                print id "\t" bound
            }
        '
)

# Print the `<AppWidgetId><TAB><provider>` records currently owned by the given
# launcher host. This reuses the record-aware new-provider parser with an empty
# "before" dump, so a provider catalog, a widget owned by another host, or a
# provider name mentioned outside a widget-id block can never satisfy the proof.
appwidget_launcher_instances() (
    dump=$1
    host=$2
    [ -s "$dump" ] || return 0
    appwidget_new_providers '' "$dump" "$host" id
)

# Print the last debug theme-refresh line for the given launcher activity that
# matches the expected night and resolved-dark values. A Settings or other
# activity line, a stale mode, or a line without the activity field is ignored.
# Exits 1 and prints nothing when no matching line exists.
theme_refresh_line() (
    log=$1
    night=$2
    dark=$3
    activity=$4
    [ -n "$activity" ] || return 1
    [ -s "$log" ] || return 1
    line=$(
        grep -F 'theme-refresh' "$log" 2>/dev/null |
            grep -F "activity=$activity " |
            grep -F "night=$night resolvedDark=$dark" |
            tail -n 1
    ) || return 1
    [ -n "$line" ] || return 1
    printf '%s\n' "$line"
)

# Succeed only when the native widget picker search/list is visible and differs
# from the pre-long-press HOME. The refactored Compose picker exposes the
# widgets_catalog test tag; the inherited picker exposes its search bar and
# widget list resource ids. A HOME page that happens to contain "Search" is not
# accepted.
widget_picker_is_ready() (
    xml=$1
    reference=${2:-}
    [ -s "$xml" ] || return 1
    if [ -n "$reference" ] && cmp -s "$reference" "$xml"; then
        return 1
    fi
    if grep -Fq 'com.android.launcher3.widgetpicker:id/widgets_catalog' "$xml"; then
        if grep -Fq 'text="Search"' "$xml" ||
            grep -Fq 'text="Featured"' "$xml" ||
            grep -Fq 'text="Browse"' "$xml"; then
            return 0
        fi
    fi
    if grep -Eq 'resource-id="[^"]*/(widgets_search_bar|search_bar_container)"' "$xml" &&
        grep -Eq 'resource-id="[^"]*/(primary_widgets_list_view|search_widgets_list_view)"' "$xml"; then
        return 0
    fi
    return 1
)

# Succeed only when the captured hierarchy really belongs to a platform
# live-wallpaper preview. The launcher settings gallery, a stale HOME, an empty
# capture and any unknown package all fail closed; a real preview must carry a
# platform wallpaper-picker package and a measured confirm/cancel control.
live_wallpaper_preview_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
    if grep -Fq 'Preview live wallpaper' "$xml"; then
        return 1
    fi
    if ! grep -Eq 'package="(com\.android\.wallpaper|com\.android\.wallpaper\.livepicker|com\.android\.wallpaperpicker|com\.google\.android\.apps\.wallpaper)[^"]*"' "$xml"; then
        return 1
    fi
    if ! grep -Eq 'text="(Set wallpaper|Set on Home screen|Set on home screen|Apply|Cancel|CANCEL)"' "$xml"; then
        return 1
    fi
    return 0
)

# The live wallpaper engine logs only lifecycle transitions in debug builds.
# A surface being created proves only that a surface existed: it does not prove
# that this engine actually became visible or drew a frame. Require the engine's
# own fresh `visibility=true` transition; surface-only, hidden-only, empty and
# unrelated logs all fail closed. Callers pass the post-baseline slice, never
# the whole shared logcat buffer.
live_wallpaper_became_visible() (
    log=$1
    [ -s "$log" ] || return 1
    grep -Eq 'DotFieldWallpaper.*visibility=true' "$log" || return 1
    return 0
)

# Derive only the log lines appended after a read-only pre-preview baseline.
# The baseline must still be an exact prefix of the later capture; a missing
# baseline, an empty capture or a rotated/truncated ring buffer fails closed, so
# a stale pre-preview `visibility=true` line can never be accepted as fresh
# post-preview evidence. The full capture stays untouched for crash/ANR checks.
live_wallpaper_preview_log_after() (
    baseline=$1
    full=$2
    out=$3
    [ -f "$baseline" ] || return 1
    [ -s "$full" ] || return 1
    baseline_lines=$(wc -l < "$baseline" | tr -d '[:space:]')
    case "$baseline_lines" in
        '' | *[!0-9]*) return 1 ;;
    esac
    if [ "$baseline_lines" -gt 0 ]; then
        prefix="$out.baseline-prefix"
        if ! head -n "$baseline_lines" "$full" > "$prefix"; then
            rm -f "$prefix"
            return 1
        fi
        if ! cmp -s "$prefix" "$baseline"; then
            rm -f "$prefix"
            return 1
        fi
        rm -f "$prefix"
    fi
    tail -n "+$((baseline_lines + 1))" "$full" > "$out" || return 1
    [ -s "$out" ] || return 1
    return 0
)

# Normalise the DEBUG-only DotFieldWallpaper visibility transitions. The engine
# now stamps every transition with its own cumulative identity token, so the
# runtime pause/resume proof can correlate one applied engine across separate
# freshly captured log slices and reject a preview, stale or different engine.
# Output one tab-free row per complete transition:
#   <engine> <visible:true|false> <posted> <drawn> <pending> <drawing>
# Incomplete, non-numeric or non-DotField lines are ignored.
live_wallpaper_visibility_events() (
    log=$1
    [ -s "$log" ] || return 0
    grep -F 'DotFieldWallpaper' "$log" 2>/dev/null |
        grep -E 'engine=[0-9]+' |
        grep -E 'visibility=(true|false)' |
        grep -E 'posted=[0-9]+' |
        grep -E 'drawn=[0-9]+' |
        grep -E 'pending=(true|false)' |
        grep -E 'drawing=(true|false)' |
        awk '
            {
                tok = vis = posted = drawn = pending = drawing = ""
                if (match($0, /engine=[0-9]+/))
                    tok = substr($0, RSTART + 7, RLENGTH - 7)
                if (match($0, /visibility=(true|false)/))
                    vis = substr($0, RSTART + 11, RLENGTH - 11)
                if (match($0, /posted=[0-9]+/))
                    posted = substr($0, RSTART + 7, RLENGTH - 7)
                if (match($0, /drawn=[0-9]+/))
                    drawn = substr($0, RSTART + 6, RLENGTH - 6)
                if (match($0, /pending=(true|false)/))
                    pending = substr($0, RSTART + 8, RLENGTH - 8)
                if (match($0, /drawing=(true|false)/))
                    drawing = substr($0, RSTART + 8, RLENGTH - 8)
                if (tok != "" && vis != "" && posted != "" && drawn != "" &&
                    pending != "" && drawing != "")
                    print tok, vis, posted, drawn, pending, drawing
            }
        '
)

# Succeed only when every parsed visibility transition in the slice belongs to
# exactly one engine token. A mixed preview/applied (or recreated) engine slice
# fails closed.
live_wallpaper_single_engine() (
    log=$1
    [ -s "$log" ] || return 1
    n=$(live_wallpaper_visibility_events "$log" |
        awk '{ seen[$1] = 1 } END { print length(seen) }')
    [ "$n" = "1" ]
)

# Print the token of the applied engine that produced a clean hidden transition
# (`visibility=false pending=false drawing=false`) in the slice. Any mix of
# engines, a missing hidden transition, or a final hidden transition that still
# has a pending/in-flight frame fails closed. The slice must be one fresh
# post-baseline tail, never the whole shared logcat buffer.
live_wallpaper_hidden_engine() (
    log=$1
    [ -s "$log" ] || return 1
    live_wallpaper_visibility_events "$log" |
        awk '
            $2 == "false" {
                seen[$1] = 1
                last = $1
            }
            END {
                if (last == "") exit 1
                if (length(seen) != 1) exit 1
                print last
            }
        '
)

# Print the cumulative drawn count of the last clean hidden transition for the
# given engine token. A final hidden transition with pending or drawing still
# true is not a quiescent hide and fails closed.
live_wallpaper_hidden_drawn() (
    log=$1
    token=$2
    [ -s "$log" ] || return 1
    [ -n "$token" ] || return 1
    live_wallpaper_visibility_events "$log" |
        awk -v token="$token" '
            $1 == token && $2 == "false" {
                drawn = $4
                pending = $5
                drawing = $6
                found = 1
            }
            END {
                if (!found) exit 1
                if (pending != "false" || drawing != "false") exit 1
                print drawn
            }
        '
)

# Print the cumulative drawn count of the last visible transition for the given
# engine token. A visible transition is logged before the resume frame is
# posted, so no pending/drawing requirement is applied here.
live_wallpaper_visible_drawn() (
    log=$1
    token=$2
    [ -s "$log" ] || return 1
    [ -n "$token" ] || return 1
    live_wallpaper_visibility_events "$log" |
        awk -v token="$token" '
            $1 == token && $2 == "true" { drawn = $4; found = 1 }
            END {
                if (!found) exit 1
                print drawn
            }
        '
)

# Succeed only when the same engine resumed with the exact cumulative drawn
# count it had at the preceding hide: no frame was drawn while hidden.
live_wallpaper_resume_unchanged() (
    log=$1
    token=$2
    expected=$3
    [ -n "$expected" ] || return 1
    actual=$(live_wallpaper_visible_drawn "$log" "$token") || return 1
    [ "$actual" = "$expected" ]
)

# Succeed only when the same engine hid again with a strictly larger cumulative
# drawn count than the prior hide: frames really resumed while visible.
live_wallpaper_hidden_frame_increase() (
    log=$1
    token=$2
    prior=$3
    case "$prior" in '' | *[!0-9]*) return 1 ;; esac
    actual=$(live_wallpaper_hidden_drawn "$log" "$token") || return 1
    [ "$actual" -gt "$prior" ]
)

# Succeed only when the captured hierarchy is the real platform live-wallpaper
# preview of this app's original wallpaper: the CI-known livepicker package and
# the exact "Dot Field (Live)" title, with a measured confirm control. The
# launcher settings gallery, an empty capture or any other wallpaper fails
# closed.
live_wallpaper_preview_is_dotfield() (
    xml=$1
    [ -s "$xml" ] || return 1
    if grep -Fq 'Preview live wallpaper' "$xml"; then
        return 1
    fi
    grep -Fq 'package="com.android.wallpaper.livepicker"' "$xml" || return 1
    grep -Fq 'Dot Field (Live)' "$xml" || return 1
    grep -Eq 'text="Set wallpaper"' "$xml" || return 1
    return 0
)

# Count the exact destination labels in a live-wallpaper confirmation dialog.
# Only exact text/content-desc matches are considered so a hint sentence that
# merely mentions Apply or a lock screen is never treated as a destination.
live_wallpaper_destination_texts() (
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
            {
                if ($0 !~ /<node[[:space:]]/) next
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (text == "" && desc == "") next
                label = (text != "") ? text : desc
                if (label == "Home screen" || label == "Home and lock screen" ||
                    label == "Home and lock" || label == "Lock screen")
                    print label
            }
        '
)

# Print the measured bounds of the single exact "Home screen" destination that
# is fully visible above the measured navigation top. Zero or multiple exact
# matches, a clipped/zero/negative control, or a non-numeric navigation top
# print nothing. The caller must never tap "Home and lock screen" or a lock
# destination, and must fail closed when this prints nothing while a destination
# dialog is present.
live_wallpaper_destination_bounds() (
    xml=$1
    nav_top=$2
    [ -s "$xml" ] || return 0
    case "$nav_top" in '' | *[!0-9]*) return 0 ;; esac
    [ "$nav_top" -gt 0 ] || return 0
    count=$(live_wallpaper_destination_texts "$xml" | grep -cx 'Home screen' || true)
    [ "$count" = "1" ] || return 0
    ui_clickable_label_within "$xml" 'Home screen' "0 0 1000000 $nav_top"
)

# Succeed when a destination dialog is present but does not offer exactly one
# exact "Home screen" choice: only lock/lock-and-home options, or duplicate
# "Home screen" labels. No destination text at all is not ambiguous here (the
# picker may have applied directly or not shown a dialog yet).
live_wallpaper_destination_ambiguous() (
    xml=$1
    [ -s "$xml" ] || return 1
    destinations=$(live_wallpaper_destination_texts "$xml" | grep -c . || true)
    [ "${destinations:-0}" -gt 0 ] || return 1
    homes=$(live_wallpaper_destination_texts "$xml" | grep -cx 'Home screen' || true)
    [ "$homes" = "1" ] && return 1
    return 0
)

# Succeed only when `dumpsys wallpaper` reports this app's DotFieldWallpaperService
# in the System wallpaper state (not the Lock/Fallback state, and not a stale
# preview entry). Any other wallpaper or a missing System section fails closed.
live_wallpaper_service_active() (
    dump=$1
    [ -s "$dump" ] || return 1
    awk '
        BEGIN { in_system = 0; found = 0 }
        /^[[:space:]]*System wallpaper state:/ { in_system = 1; next }
        /^[[:space:]]*(Lock|Fallback) wallpaper state:/ { in_system = 0; next }
        in_system && /DotFieldWallpaperService/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "$dump"
)
