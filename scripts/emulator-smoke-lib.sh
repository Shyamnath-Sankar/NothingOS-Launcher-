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

# Succeed only when the real HOME long-press options popup is open. The
# OptionsPopupView/DeepShortcutView class plus the Widgets item and a home-level
# option reject an item-specific menu or a page that merely contains the word
# "Widgets".
home_popup_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
    if ! grep -Fq 'class="com.android.launcher3.views.OptionsPopupView"' "$xml" &&
        ! grep -Fq 'class="com.android.launcher3.shortcuts.DeepShortcutView"' "$xml"; then
        return 1
    fi
    grep -Fq 'text="Widgets"' "$xml" || return 1
    grep -Fq 'text="Home settings"' "$xml" ||
        grep -Fq 'text="Edit home screen"' "$xml" ||
        grep -Fq 'text="Wallpapers"' "$xml" ||
        grep -Fq 'text="Wallpaper &amp; style"' "$xml" ||
        return 1
    return 0
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
