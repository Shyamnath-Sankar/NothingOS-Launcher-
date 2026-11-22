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

# Succeed when the point ($2,$3) is not inside a labelled clickable node. This
# keeps the HOME long-press on empty workspace instead of an app icon, folder or
# widget that would open an item-specific menu.
ui_point_is_free() (
    xml=$1
    px=$2
    py=$3
    [ -s "$xml" ] || return 1
    case "$px" in '' | *[!0-9]*) return 1 ;; esac
    case "$py" in '' | *[!0-9]*) return 1 ;; esac
    occupied=$(tr '>' '\n' < "$xml" |
        awk -v px="$px" -v py="$py" '
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
                if (attr($0, "clickable") != "true") next
                text = attr($0, "text")
                desc = attr($0, "content-desc")
                if (text == "" && desc == "") next
                bounds = attr($0, "bounds")
                if (bounds == "") next
                x1 = v_of(bounds, 1)
                y1 = v_of(bounds, 2)
                x2 = v_of(bounds, 3)
                y2 = v_of(bounds, 4)
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
# centre when a labelled clickable item occupies it. Prints "x y".
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
    for pct in 50 60 70 40 30 80 20; do
        y=$((band_top + band * pct / 100))
        if ui_point_is_free "$xml" "$x" "$y"; then
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
home_widget_bounds() (
    xml=$1
    reference=${2:-}
    [ -s "$xml" ] || return 0
    {
        if [ -n "$reference" ] && [ -s "$reference" ]; then
            tr '>' '\n' < "$reference" |
                awk '{ print "R\t" $0 }'
        fi
        tr '>' '\n' < "$xml" |
            awk '{ print "C\t" $0 }'
    } |
        awk -F '\t' '
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
                selfclose = (rec ~ /\/[[:space:]]*$/)
                parent_ws = (sp > 0 ? stack_ws[sp] : 0)
                parent_preview = (sp > 0 ? stack_preview[sp] : 0)
                ws = parent_ws || is_workspace(rid, cls)
                preview = parent_preview || is_preview(rid, cls)
                if (kind == "C" && ws) cur_saw_ws = 1
                if (cls ~ /AppWidgetHostView/ &&
                    bounds ~ /^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$/) {
                    if (kind == "R") {
                        if (!preview) seen[bounds] = 1
                    } else if (!preview) {
                        if (ws && first_ws == "") first_ws = bounds
                        if (!ws && first_nonws == "") first_nonws = bounds
                    }
                }
                if (!selfclose) {
                    sp++
                    stack_ws[sp] = ws
                    stack_preview[sp] = preview
                }
            }
            END {
                if (first_ws != "") chosen = first_ws
                else if (!cur_saw_ws) chosen = first_nonws
                if (chosen != "" && !(chosen in seen)) emit(chosen)
            }
        '
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
# the running package, and its provider class is exactly one of the two DotWel
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
                    class != "app.dotwel.widgets.DotWelBatteryWidgetProvider") {
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
