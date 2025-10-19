#!/usr/bin/env bash
# setup-x-resize-xfce-kali.sh
# https://github.com/h0ek/x-resize
# Project: x-resize — unified RandR auto-resize helpers
# Variant: Kali + XFCE on Xorg (KVM/SPICE) with evdev absolute-pointer calibration
#
# What this installer does:
#   - Ensures deps: xrandr, xev, xinput, xserver-xorg-input-evdev
#   - Adds /etc/X11/xorg.conf.d/70-tablet-evdev.conf (QEMU/SPICE tablets → evdev, Absolute)
#   - Installs ~/.local/bin/x-resize-xfce (RandR listener → xrandr --auto + evdev Axis Calibration to current WxH)
#   - Creates & enables ~/.config/systemd/user/x-resize-xfce.service
#
# Requirements:
#   - Xorg session (XDG_SESSION_TYPE=x11)
#   - At least one absolute pointing device (QEMU USB Tablet or SPICE vdagent tablet)
#
# Usage:
#   chmod +x setup-x-resize-xfce-kali.sh
#   ./setup-x-resize-xfce-kali.sh
#
# After install:
#   - Log out/in (or reboot) so Xorg reloads InputClass (evdev)
#   - In SPICE viewer: Auto resize = ON, Scale Display = OFF, Zoom 100%
#
# Logs:
#   journalctl --user -u x-resize-xfce -f

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Do NOT run as root. Run as your normal user."
  exit 1
fi

# --- paths ---
BIN_DIR="${HOME}/.local/bin"
SCRIPT_FILE="${BIN_DIR}/x-resize-xfce"
UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${UNIT_DIR}/x-resize-xfce.service"
XORG_DIR="/etc/X11/xorg.conf.d"
EVDEV_FILE="${XORG_DIR}/70-tablet-evdev.conf"

mkdir -p "${BIN_DIR}" "${UNIT_DIR}"

# --- deps (xev/xrandr/xinput/evdev) ---
missing=()
command -v xrandr >/dev/null 2>&1 || missing+=("x11-xserver-utils")
command -v xev     >/dev/null 2>&1 || missing+=("x11-utils")
command -v xinput  >/dev/null 2>&1 || missing+=("xinput")
dpkg -s xserver-xorg-input-evdev >/dev/null 2>&1 || missing+=("xserver-xorg-input-evdev")
if (( ${#missing[@]} )); then
  echo "Installing required packages: ${missing[*]} ..."
  sudo apt update
  sudo apt install -y "${missing[@]}"
fi

# --- Xorg InputClass: force tablets to evdev Absolute ---
echo "Writing ${EVDEV_FILE} ..."
sudo mkdir -p "${XORG_DIR}"
sudo tee "${EVDEV_FILE}" >/dev/null <<'EOF'
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

# --- payload script (RandR listener + evdev calibration) ---
echo "Installing ${SCRIPT_FILE} ..."
cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash
# x-resize-xfce: XFCE/Xorg RandR auto-resize + evdev axis calibration (user mode)
# Fixes absolute-pointer offset when SPICE yields odd modes (e.g., 1809x1055).
# Per RandR event:
#   1) xrandr --auto on active output
#   2) read current WxH
#   3) set "Evdev Axis Calibration" = 0..W-1, 0..H-1 on tablets
#   4) apply a no-op transform to force Xorg to re-evaluate maps

set -euo pipefail
log(){ logger -t x-resize-xfce -- "$*"; echo "[x-resize-xfce] $*"; }

# Require Xorg
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
  log "Not X11 (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}); exiting."
  exit 0
fi

: "${DISPLAY:?DISPLAY not set}"
: "${XAUTHORITY:=${HOME}/.Xauthority}"
export DISPLAY XAUTHORITY

TABLETS=("QEMU QEMU USB Tablet" "spice vdagent tablet")

pick_output(){ xrandr --current | awk '/ connected primary/{print $1;exit} / connected/{print $1;exit}'; }
current_mode(){
  local m
  m="$(xrandr | awk '/\*/{print $1;exit}')"   # e.g., 1809x1055
  if [ -z "$m" ]; then
    m="$(xrandr | awk -F'current ' 'NR==1{split($2,a,","); gsub(/ /,"",a[1]); print a[1]}')"  # Screen 0: current WxH
  fi
  echo "$m"
}

calibrate_evdev_to(){
  local wh="$1" w h
  w="${wh%x*}"; h="${wh#*x}"
  for dev in "${TABLETS[@]}"; do
    if xinput --list --name-only | grep -Fxq "$dev"; then
      log "Calibrate $dev -> ${w}x${h}"
      xinput --set-prop "$dev" "Evdev Axis Calibration" 0 $((w-1)) 0 $((h-1)) 2>/dev/null || true
      xinput --set-prop "$dev" "Evdev Axis Inversion" 0 0 2>/dev/null || true
    fi
  done
}

apply_once(){
  local out cur
  out="$(pick_output)"; [ -n "$out" ] || { log "No connected outputs"; return 0; }

  # 1) Let SPICE propose size
  xrandr --output "$out" --auto || true

  # 2) Calibrate evdev axes to current screen size
  cur="$(current_mode)"
  [ -n "$cur" ] && calibrate_evdev_to "$cur"

  # 3) No-op transform (forces Xorg to re-evaluate maps). No flicker.
  xrandr --output "$out" --transform 1,0,0,0,1,0,0,0,1 || true
}

# Initial pass
apply_once

# Debounce (300 ms)
last=0
debounce_ms=300
now_ms(){ date +%s%3N 2>/dev/null || echo $(( $(date +%s)*1000 )); }
should_run(){ local n; n=$(now_ms); if (( n-last >= debounce_ms )); then last=$n; return 0; fi; return 1; }

log "Listening for RandR changes on ${DISPLAY} ..."
xev -root -event randr 2>/dev/null | grep --line-buffered 'XRROutputChangeNotifyEvent' | \
while read -r _; do
  if should_run; then
    apply_once
  fi
done
EOF
chmod +x "${SCRIPT_FILE}"

# --- systemd --user service ---
echo "Installing ${SERVICE_FILE} ..."
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=x-resize (XFCE/Kali): Xorg RandR auto-resize + evdev calibration (user)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${SCRIPT_FILE}
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

# --- enable user service ---
echo "Enabling user service..."
systemctl --user daemon-reload
systemctl --user enable --now x-resize-xfce

echo
echo "OK: enabled user service 'x-resize-xfce.service'."
echo "IMPORTANT: Log out/in (or reboot) so Xorg reloads ${EVDEV_FILE}."
echo "Viewer: Auto resize=ON, Scale=OFF, Zoom=100%"
echo "Logs: journalctl --user -u x-resize-xfce -f"
