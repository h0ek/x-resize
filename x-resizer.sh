#!/usr/bin/env bash
set -euo pipefail

PROJECT="x-resize"
BIN_DIR="${HOME}/.local/bin"
SCRIPT_FILE="${BIN_DIR}/x-resize"
UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${UNIT_DIR}/x-resize.service"
CONFIG_DIR="${HOME}/.config/x-resize"
CONFIG_FILE="${CONFIG_DIR}/config"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/x-resize"
STATE_FILE="${STATE_DIR}/install.env"
XORG_DIR="/etc/X11/xorg.conf.d"
EVDEV_FILE="${XORG_DIR}/70-tablet-evdev.conf"
EVDEV_BACKUP="${STATE_DIR}/70-tablet-evdev.conf.backup"

log() {
    printf '[x-resize] %s\n' "$*"
}

die() {
    printf '[x-resize] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  ./x-resizer.sh                 Interactive install/uninstall menu
  ./x-resizer.sh auto            Auto-detect and install the recommended profile
  ./x-resizer.sh generic         Generic XFCE/MATE Xorg profile
  ./x-resizer.sh kali            Kali XFCE profile with evdev calibration
  ./x-resizer.sh arch            Arch XFCE profile with evdev calibration
  ./x-resizer.sh mate            MATE Xorg profile
  ./x-resizer.sh uninstall       Remove x-resize and managed configuration
  ./x-resizer.sh status          Show service/configuration status
  ./x-resizer.sh help            Show this help

Aliases:
  debian, debian-xfce, generic-xfce -> generic
  kali-xfce                       -> kali
  arch-xfce                       -> arch
  parrot, parrot-mate             -> mate
EOF
}

require_normal_user() {
    if [[ ${EUID} -eq 0 ]]; then
        die "Do not run this installer as root. Run it as your normal desktop user; sudo is requested only when needed."
    fi
}

os_id() {
    local id="unknown"
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        id="${ID:-unknown}"
    fi
    printf '%s\n' "${id,,}"
}

desktop_name() {
    printf '%s\n' "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}" | tr '[:upper:]' '[:lower:]'
}

detect_profile() {
    local id desktop
    id="$(os_id)"
    desktop="$(desktop_name)"

    if [[ "$desktop" == *xfce* ]]; then
        case "$id" in
            kali) printf '%s\n' "kali"; return ;;
            arch|manjaro|endeavouros) printf '%s\n' "arch"; return ;;
        esac
    fi

    if [[ "$desktop" == *mate* ]]; then
        printf '%s\n' "mate"
        return
    fi

    printf '%s\n' "generic"
}

profile_description() {
    case "$1" in
        generic) printf '%s\n' "Generic XFCE/MATE on Xorg" ;;
        kali) printf '%s\n' "Kali XFCE on Xorg + evdev absolute-pointer calibration" ;;
        arch) printf '%s\n' "Arch-family XFCE on Xorg + evdev absolute-pointer calibration" ;;
        mate) printf '%s\n' "MATE on Xorg" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

interactive_menu() {
    local detected choice
    detected="$(detect_profile)"

    printf '\nDetected: OS=%s, desktop=%s, session=%s\n' "$(os_id)" "$(desktop_name)" "${XDG_SESSION_TYPE:-unknown}" >&2
    printf 'Recommended profile: %s\n\n' "$(profile_description "$detected")" >&2
    printf '  1) Install recommended profile\n' >&2
    printf '  2) Generic XFCE/MATE\n' >&2
    printf '  3) Kali XFCE + evdev calibration\n' >&2
    printf '  4) Arch XFCE + evdev calibration\n' >&2
    printf '  5) MATE\n' >&2
    printf '  6) Uninstall x-resize\n' >&2
    printf '  7) Status\n' >&2
    printf '  0) Cancel\n\n' >&2
    read -r -p 'Choose: ' choice

    case "$choice" in
        1) printf '%s\n' "$detected" ;;
        2) printf '%s\n' "generic" ;;
        3) printf '%s\n' "kali" ;;
        4) printf '%s\n' "arch" ;;
        5) printf '%s\n' "mate" ;;
        6) printf '%s\n' "uninstall" ;;
        7) printf '%s\n' "status" ;;
        0) printf '%s\n' "cancel" ;;
        *) die "Invalid choice: $choice" ;;
    esac
}

normalize_profile() {
    case "$1" in
        auto) detect_profile ;;
        generic|debian|debian-xfce|generic-xfce) printf '%s\n' "generic" ;;
        kali|kali-xfce) printf '%s\n' "kali" ;;
        arch|arch-xfce) printf '%s\n' "arch" ;;
        mate|parrot|parrot-mate) printf '%s\n' "mate" ;;
        uninstall|status|help|cancel) printf '%s\n' "$1" ;;
        *) die "Unknown profile/action: $1" ;;
    esac
}

package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' "apt"
    elif command -v pacman >/dev/null 2>&1; then
        printf '%s\n' "pacman"
    else
        printf '%s\n' "unknown"
    fi
}

apt_missing() {
    local pkg
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || printf '%s\n' "$pkg"
    done
}

pacman_missing() {
    local pkg
    for pkg in "$@"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 || printf '%s\n' "$pkg"
    done
}

install_dependencies() {
    local profile="$1" pm
    local -a packages missing
    pm="$(package_manager)"

    case "$pm" in
        apt)
            packages=(x11-xserver-utils x11-utils spice-vdagent)
            if [[ "$profile" == "kali" ]]; then
                packages+=(xinput xfconf xserver-xorg-input-evdev)
            fi
            if [[ "$(systemd-detect-virt 2>/dev/null || true)" == "kvm" ]]; then
                packages+=(qemu-guest-agent)
            fi
            mapfile -t missing < <(apt_missing "${packages[@]}")
            if (( ${#missing[@]} )); then
                log "Installing required packages: ${missing[*]}"
                sudo apt-get update
                sudo apt-get install -y "${missing[@]}"
            fi
            ;;
        pacman)
            packages=(xorg-xrandr xorg-xev spice-vdagent)
            if [[ "$profile" == "arch" ]]; then
                packages+=(xorg-xinput xfconf xf86-input-evdev)
            fi
            if [[ "$(systemd-detect-virt 2>/dev/null || true)" == "kvm" ]]; then
                packages+=(qemu-guest-agent)
            fi
            mapfile -t missing < <(pacman_missing "${packages[@]}")
            if (( ${#missing[@]} )); then
                log "Installing required packages: ${missing[*]}"
                sudo pacman -S --needed --noconfirm "${missing[@]}"
            fi
            ;;
        *)
            die "Unsupported package manager. Install xrandr, xev, spice-vdagent and the profile-specific packages manually."
            ;;
    esac
}

is_repo_legacy_evdev() {
    [[ -f "$EVDEV_FILE" ]] || return 1
    grep -Fq 'Identifier "QEMU USB Tablet via evdev"' "$EVDEV_FILE" 2>/dev/null &&
        grep -Fq 'Identifier "SPICE vdagent tablet via evdev"' "$EVDEV_FILE" 2>/dev/null
}

write_evdev_config() {
    mkdir -p "$STATE_DIR"

    if [[ -f "$EVDEV_FILE" ]] && grep -Fq '# Managed by x-resize' "$EVDEV_FILE" 2>/dev/null; then
        log "Updating managed ${EVDEV_FILE}."
    elif [[ -f "$EVDEV_FILE" ]]; then
        if is_repo_legacy_evdev; then
            log "Replacing legacy x-resize evdev configuration."
            rm -f "$EVDEV_BACKUP"
        else
            log "Backing up existing ${EVDEV_FILE} to ${EVDEV_BACKUP}."
            sudo cat "$EVDEV_FILE" > "$EVDEV_BACKUP"
        fi
    else
        rm -f "$EVDEV_BACKUP"
    fi

    log "Writing ${EVDEV_FILE}."
    sudo mkdir -p "$XORG_DIR"
    sudo tee "$EVDEV_FILE" >/dev/null <<'EOF'
# Managed by x-resize
Section "InputClass"
    Identifier "QEMU USB Tablet via evdev"
    MatchProduct "QEMU QEMU USB Tablet"
    Driver "evdev"
    Option "Mode" "Absolute"
EndSection

Section "InputClass"
    Identifier "SPICE vdagent tablet via evdev"
    MatchProduct "spice vdagent tablet"
    Driver "evdev"
    Option "Mode" "Absolute"
EndSection
EOF
}

restore_evdev_config() {
    if [[ -f "$EVDEV_FILE" ]] && grep -Fq '# Managed by x-resize' "$EVDEV_FILE" 2>/dev/null; then
        if [[ -f "$EVDEV_BACKUP" ]]; then
            log "Restoring previous ${EVDEV_FILE}."
            sudo cp "$EVDEV_BACKUP" "$EVDEV_FILE"
        else
            log "Removing managed ${EVDEV_FILE}."
            sudo rm -f "$EVDEV_FILE"
        fi
    fi
    rm -f "$EVDEV_BACKUP"
}

cleanup_legacy_user_installations() {
    local unit
    for unit in x-resize.service x-resize-xfce.service mate-x-autoresize.service; do
        systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
    done

    rm -f \
        "${UNIT_DIR}/x-resize.service" \
        "${UNIT_DIR}/x-resize-xfce.service" \
        "${UNIT_DIR}/mate-x-autoresize.service" \
        "${BIN_DIR}/x-resize" \
        "${BIN_DIR}/x-resize-xfce" \
        "${BIN_DIR}/mate-x-autoresize"

    systemctl --user daemon-reload
}

cleanup_legacy_system_installation() {
    local legacy_unit="/etc/systemd/system/x-resize.service"
    local legacy_script="/usr/local/bin/x-resize"

    if [[ -f "$legacy_unit" ]] && grep -Fq '/usr/local/bin/x-resize' "$legacy_unit" 2>/dev/null; then
        log "Removing legacy system-wide x-resize installation."
        sudo systemctl disable --now x-resize.service >/dev/null 2>&1 || true
        sudo rm -f "$legacy_unit"
        if [[ -f "$legacy_script" ]] && grep -Fq 'XRROutputChangeNotifyEvent' "$legacy_script" 2>/dev/null; then
            sudo rm -f "$legacy_script"
        fi
        sudo systemctl daemon-reload
        sudo systemctl reset-failed x-resize.service >/dev/null 2>&1 || true
    fi
}

write_runtime() {
    mkdir -p "$BIN_DIR"
    cat > "$SCRIPT_FILE" <<'RUNTIME_EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.config/x-resize/config"
CALIBRATE_EVDEV=0
PRESERVE_XFCE_SCALE=1
NARROW_CAP_W=1920
NARROW_CAP_H=1440
WIDE_CAP_W=2560
WIDE_CAP_H=1440
NARROW_RATIO_MAX=1.67
ASPECT_TOLERANCE=0.08
DEBOUNCE_MS=350

if [[ -r "$CONFIG_FILE" ]]; then
    . "$CONFIG_FILE"
fi

log() {
    logger -t x-resize -- "$*" 2>/dev/null || true
    printf '[x-resize] %s\n' "$*"
}

if [[ -z "${XDG_SESSION_TYPE:-}" ]]; then
    log "XDG_SESSION_TYPE is not available yet; retrying through systemd."
    exit 1
fi

if [[ "${XDG_SESSION_TYPE}" != "x11" ]]; then
    log "Session type is ${XDG_SESSION_TYPE}; Xorg is required."
    exit 0
fi

if [[ -z "${DISPLAY:-}" ]]; then
    log "DISPLAY is not available yet; retrying through systemd."
    exit 1
fi

: "${XAUTHORITY:=${HOME}/.Xauthority}"
export DISPLAY XAUTHORITY

TABLETS=("QEMU QEMU USB Tablet" "spice vdagent tablet")

pick_output() {
    xrandr --current | awk '/ connected primary/{print $1;exit} / connected/{print $1;exit}'
}

current_mode() {
    local out="$1"
    xrandr --current | awk -v out="$out" '
        $1 == out && $2 == "connected" { found=1; next }
        found && $0 !~ /^[[:space:]]/ { exit }
        found && $1 ~ /^[0-9]+x[0-9]+$/ && $0 ~ /\*/ { print $1; exit }
    '
}

list_modes() {
    local out="$1"
    xrandr --current | awk -v out="$out" '
        $1 == out && $2 == "connected" { found=1; next }
        found && $0 !~ /^[[:space:]]/ { exit }
        found && $1 ~ /^[0-9]+x[0-9]+$/ { print $1 }
    ' | awk '!seen[$0]++'
}

mode_exists() {
    local out="$1" wanted="$2"
    list_modes "$out" | grep -Fxq "$wanted"
}

current_scale() {
    local out="$1" scale="1.000000"

    if [[ "$PRESERVE_XFCE_SCALE" != "1" ]] || ! command -v xfconf-query >/dev/null 2>&1; then
        printf '%s\n' "$scale"
        return
    fi

    scale="$(xfconf-query -c displays -p "/Default/${out}/Scale" 2>/dev/null || true)"
    if [[ ! "$scale" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        scale="1.000000"
    fi
    printf '%s\n' "$scale"
}

calibrate_evdev_to() {
    local wh="$1" w h dev
    [[ "$CALIBRATE_EVDEV" == "1" ]] || return 0
    command -v xinput >/dev/null 2>&1 || return 0

    w="${wh%x*}"
    h="${wh#*x}"

    for dev in "${TABLETS[@]}"; do
        if xinput --list --name-only | grep -Fxq "$dev"; then
            if xinput --list-props "$dev" 2>/dev/null | grep -Fq 'Evdev Axis Calibration'; then
                log "Calibrate ${dev} -> ${w}x${h}"
                xinput --set-prop "$dev" "Evdev Axis Calibration" 0 $((w - 1)) 0 $((h - 1)) 2>/dev/null || true
                xinput --set-prop "$dev" "Evdev Axis Inversion" 0 0 2>/dev/null || true
            fi
        fi
    done
}

select_capped_mode() {
    local out="$1" desired="$2" cap_w="$3" cap_h="$4"
    local dw dh target_w target_h

    IFS=x read -r dw dh <<< "$desired"
    target_w="$dw"
    target_h="$dh"
    (( target_w > cap_w )) && target_w="$cap_w"
    (( target_h > cap_h )) && target_h="$cap_h"

    list_modes "$out" | awk \
        -v dw="$dw" -v dh="$dh" \
        -v tw="$target_w" -v th="$target_h" \
        -v tol="$ASPECT_TOLERANCE" '
        function abs(x) { return x < 0 ? -x : x }
        {
            split($1, d, "x")
            w=d[1]+0
            h=d[2]+0
            if (w > tw || h > th || w <= 0 || h <= 0)
                next

            desired_ratio=dw/dh
            ratio=w/h
            diff=abs(ratio-desired_ratio)/desired_ratio
            area=w*h

            if (diff <= tol) {
                if (!good_found || area > good_area) {
                    good_found=1
                    good=$1
                    good_area=area
                }
            }

            if (!fallback_found || area > fallback_area) {
                fallback_found=1
                fallback=$1
                fallback_area=area
            }
        }
        END {
            if (good_found) print good
            else if (fallback_found) print fallback
        }
    '
}

cap_for_mode() {
    local mode="$1" w h ratio
    IFS=x read -r w h <<< "$mode"

    if (( w <= WIDE_CAP_W && h <= WIDE_CAP_H )); then
        printf '%s %s\n' "$w" "$h"
        return
    fi

    ratio="$(awk -v w="$w" -v h="$h" 'BEGIN { if (h == 0) print 99; else printf "%.4f", w/h }')"
    if awk -v r="$ratio" -v max="$NARROW_RATIO_MAX" 'BEGIN { exit !(r <= max) }'; then
        printf '%s %s\n' "$NARROW_CAP_W" "$NARROW_CAP_H"
    else
        printf '%s %s\n' "$WIDE_CAP_W" "$WIDE_CAP_H"
    fi
}

apply_once() {
    local out scale desired dw dh cap_w cap_h selected final

    out="$(pick_output)"
    if [[ -z "$out" ]]; then
        log "No connected outputs."
        return 0
    fi

    scale="$(current_scale "$out")"

    xrandr --output "$out" --auto || true
    sleep 0.05

    desired="$(current_mode "$out")"
    if [[ -z "$desired" ]]; then
        log "Could not determine current mode for ${out}."
        return 0
    fi

    IFS=x read -r dw dh <<< "$desired"
    read -r cap_w cap_h < <(cap_for_mode "$desired")

    selected="$desired"
    if (( dw > cap_w || dh > cap_h )); then
        selected="$(select_capped_mode "$out" "$desired" "$cap_w" "$cap_h")"
        if [[ -z "$selected" ]]; then
            selected="$desired"
        fi
    fi

    if [[ "$selected" != "$desired" ]]; then
        if mode_exists "$out" "$selected"; then
            if ! xrandr --output "$out" --mode "$selected"; then
                log "Mode ${selected} changed during resize; keeping ${desired}."
                selected="$desired"
            fi
        else
            log "Mode ${selected} disappeared during resize; keeping ${desired}."
            selected="$desired"
        fi
    fi

    final="$(current_mode "$out")"
    [[ -n "$final" ]] || final="$selected"

    if [[ "$PRESERVE_XFCE_SCALE" == "1" ]] && command -v xfconf-query >/dev/null 2>&1; then
        xrandr --output "$out" --transform "$scale,0,0,0,$scale,0,0,0,1" || true
    fi

    calibrate_evdev_to "$final"
    log "request=${desired} cap=${cap_w}x${cap_h} selected=${final} output=${out}"
}

apply_once

last=0
now_ms() {
    date +%s%3N 2>/dev/null || echo $(( $(date +%s) * 1000 ))
}

should_run() {
    local now
    now="$(now_ms)"
    if (( now - last >= DEBOUNCE_MS )); then
        last="$now"
        return 0
    fi
    return 1
}

log "Listening for RandR events on ${DISPLAY}."
xev -root -event randr 2>/dev/null | \
    grep --line-buffered 'XRROutputChangeNotifyEvent' | \
    while read -r _; do
        if should_run; then
            apply_once
        fi
    done
RUNTIME_EOF
    chmod +x "$SCRIPT_FILE"
}

write_config() {
    local profile="$1" calibrate=0
    [[ "$profile" == "kali" || "$profile" == "arch" ]] && calibrate=1

    mkdir -p "$CONFIG_DIR" "$STATE_DIR"
    cat > "$CONFIG_FILE" <<EOF
CALIBRATE_EVDEV=${calibrate}
PRESERVE_XFCE_SCALE=1
NARROW_CAP_W=1920
NARROW_CAP_H=1440
WIDE_CAP_W=2560
WIDE_CAP_H=1440
NARROW_RATIO_MAX=1.67
ASPECT_TOLERANCE=0.08
DEBOUNCE_MS=350
EOF

    {
        printf 'PROFILE=%q\n' "$profile"
        printf 'CALIBRATE_EVDEV=%q\n' "$calibrate"
    } > "$STATE_FILE"
}

write_service() {
    mkdir -p "$UNIT_DIR"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-resize: adaptive Xorg RandR resize for KVM/SPICE guests
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${SCRIPT_FILE}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

install_profile() {
    local profile="$1" calibrate=0

    log "Installing profile: $(profile_description "$profile")"
    install_dependencies "$profile"

    cleanup_legacy_user_installations
    cleanup_legacy_system_installation

    if [[ "$profile" == "kali" || "$profile" == "arch" ]]; then
        calibrate=1
        write_evdev_config
    else
        restore_evdev_config
    fi

    write_runtime
    write_config "$profile"
    write_service

    systemctl --user import-environment DISPLAY XAUTHORITY XDG_SESSION_TYPE >/dev/null 2>&1 || true
    systemctl --user daemon-reload
    systemctl --user enable --now x-resize.service

    printf '\nInstalled x-resize.\n'
    printf 'Profile: %s\n' "$(profile_description "$profile")"
    printf 'Service: systemctl --user status x-resize\n'
    printf 'Logs:    journalctl --user -u x-resize -f\n'
    printf 'Config:  %s\n' "$CONFIG_FILE"
    printf 'Viewer:  Auto resize VM with window = ON, Scale Display = ON\n'
    printf 'XFCE:    Display scale 1.0 is recommended; adaptive resolution capping handles HiDPI windows.\n'
    if (( calibrate == 1 )); then
        printf 'Re-login or reboot once so Xorg loads %s.\n' "$EVDEV_FILE"
    fi
}

uninstall_all() {
    log "Uninstalling x-resize."

    cleanup_legacy_user_installations
    cleanup_legacy_system_installation
    restore_evdev_config

    rm -f "$CONFIG_FILE" "$STATE_FILE"
    rmdir "$CONFIG_DIR" 2>/dev/null || true
    rmdir "$STATE_DIR" 2>/dev/null || true

    printf '\nx-resize removed. Installed dependency packages were left in place.\n'
}

show_status() {
    printf 'Detected profile: %s\n' "$(profile_description "$(detect_profile)")"
    if [[ -r "$STATE_FILE" ]]; then
        printf 'Installed state:\n'
        sed 's/^/  /' "$STATE_FILE"
    else
        printf 'Installed state: none\n'
    fi
    if [[ -r "$CONFIG_FILE" ]]; then
        printf 'Configuration:\n'
        sed 's/^/  /' "$CONFIG_FILE"
    fi
    printf '\nService:\n'
    systemctl --user status x-resize.service --no-pager || true
}

main() {
    local action
    require_normal_user

    if (( $# == 0 )); then
        action="$(interactive_menu)"
    else
        action="$(normalize_profile "$1")"
    fi

    case "$action" in
        generic|kali|arch|mate) install_profile "$action" ;;
        uninstall) uninstall_all ;;
        status) show_status ;;
        help) usage ;;
        cancel) exit 0 ;;
        *) die "Unhandled action: $action" ;;
    esac
}

main "$@"
