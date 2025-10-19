#!/usr/bin/env bash
# setup-x-resize-xfce.sh
# https://github.com/h0ek/x-resize
# Project: x-resize — unified RandR auto-resize helpers
# Variant: Generic Xorg (XFCE/MATE/etc.) using systemd --user
#
# What this installer does:
#   - Ensures deps: xrandr, xev
#   - Installs ~/.local/bin/x-resize (RandR listener → xrandr --auto)
#   - Creates & enables ~/.config/systemd/user/x-resize.service
#
# Requirements:
#   - Xorg session (XDG_SESSION_TYPE=x11)
#
# Usage:
#   chmod +x setup-x-resize-xfce.sh
#   ./setup-x-resize-xfce.sh
#
# Logs:
#   journalctl --user -u x-resize -f

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Do NOT run as root. Run as your normal user."
  exit 1
fi

# --- deps (xrandr/xev) ---
missing=()
command -v xrandr >/dev/null 2>&1 || missing+=("x11-xserver-utils")
command -v xev     >/dev/null 2>&1 || missing+=("x11-utils")
if (( ${#missing[@]} )); then
  echo "Installing required packages: ${missing[*]} ..."
  sudo apt update
  sudo apt install -y "${missing[@]}"
fi

# --- paths ---
BIN_DIR="${HOME}/.local/bin"
SCRIPT_FILE="${BIN_DIR}/x-resize"
UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${UNIT_DIR}/x-resize.service"

mkdir -p "${BIN_DIR}" "${UNIT_DIR}"

# --- payload script (generic, Xorg-only) ---
cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash
# x-resize: generic Xorg RandR auto-resize (user mode)
# Behavior:
#   - On start and on each RandR XRROutputChange: run `xrandr --auto` for the active output.
#   - Debounce to avoid loops. Exit on Wayland.
#   - No device tweaks (works where DE already cooperates).

set -euo pipefail

log(){ logger -t x-resize -- "$*"; echo "[x-resize] $*"; }

# Require Xorg
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
  log "Not X11 (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}); exiting."
  exit 0
fi

: "${DISPLAY:?DISPLAY not set}"
: "${XAUTHORITY:=${HOME}/.Xauthority}"
export DISPLAY XAUTHORITY

# Pick active/first connected output
pick_output() {
  local out
  out="$(xrandr --current | awk '/ connected primary/{print $1;exit} / connected/{print $1;exit}')"
  echo "$out"
}

apply_auto() {
  local out; out="$(pick_output)"
  if [ -n "$out" ]; then
    log "xrandr --output ${out} --auto"
    xrandr --output "${out}" --auto || true
  else
    log "No connected outputs."
  fi
}

# Initial run
apply_auto

# Debounce (300ms)
last=0
debounce_ms=300
now_ms(){ date +%s%3N 2>/dev/null || echo $(( $(date +%s) * 1000 )); }
should_run(){ local n; n=$(now_ms); if (( n-last >= debounce_ms )); then last=$n; return 0; fi; return 1; }

# Listen for RandR events
log "Listening for RandR events on ${DISPLAY} ..."
xev -root -event randr 2>/dev/null | \
grep --line-buffered 'XRROutputChangeNotifyEvent' | \
while read -r _; do
  if should_run; then
    apply_auto
  fi
done
EOF
chmod +x "${SCRIPT_FILE}"

# --- systemd --user service ---
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=x-resize (Generic): Xorg RandR auto-resize (user)
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
systemctl --user daemon-reload
systemctl --user enable --now x-resize

echo "OK: enabled user service 'x-resize'."
echo "Logs: journalctl --user -u x-resize -f"
echo "Tip: If it doesn't start at login: loginctl enable-linger $USER"
