#!/usr/bin/env bash
# setup-x-resize-mate.sh
# https://github.com/h0ek/x-resize
# Project: x-resize — unified RandR auto-resize helpers
# Variant: MATE on Xorg (Parrot/KVM/SPICE) using systemd --user
#
# What this installer does:
#   - Ensures deps: xrandr, xev
#   - Installs ~/.local/bin/mate-x-autoresize (RandR listener → xrandr --auto)
#   - Creates & enables ~/.config/systemd/user/mate-x-autoresize.service
#
# Requirements:
#   - Xorg session (XDG_SESSION_TYPE=x11)
#
# Usage:
#   chmod +x setup-x-resize-mate.sh
#   ./setup-x-resize-mate.sh
#
# Logs:
#   journalctl --user -u mate-x-autoresize -f

set -euo pipefail

# --- deps (xev/xrandr) ---
if ! command -v xrandr >/dev/null 2>&1; then
  echo "Installing xrandr (x11-xserver-utils) ..."
  sudo apt update && sudo apt install -y x11-xserver-utils
fi
if ! command -v xev >/dev/null 2>&1; then
  echo "Installing xev (x11-utils) ..."
  sudo apt update && sudo apt install -y x11-utils
fi

# --- paths ---
BIN_DIR="${HOME}/.local/bin"
SCRIPT_FILE="${BIN_DIR}/mate-x-autoresize"
UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${UNIT_DIR}/mate-x-autoresize.service"

mkdir -p "${BIN_DIR}" "${UNIT_DIR}"

# --- payload script ---
cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash
# mate-x-autoresize: MATE/Xorg RandR auto-resize (user mode)
# Behavior:
#   - On start and on each XRROutputChange: run `xrandr --auto` for the active output.
#   - Debounce to avoid loops. Exit on Wayland.

set -euo pipefail

log(){ logger -t mate-x-autoresize -- "$*"; echo "[mate-x-autoresize] $*"; }

# Require Xorg
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
  log "Not X11 (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}); exiting."
  exit 0
fi

: "${DISPLAY:?DISPLAY not set}"
: "${XAUTHORITY:=${HOME}/.Xauthority}"
export DISPLAY XAUTHORITY

# Prefer common virtual outputs; fallback to first connected
pick_output() {
  local out
  out="$(xrandr --current | awk '/ connected/{print $1}' | \
        grep -E '^Virtual-|^VIRT|^QXL|^VMware|^DP-|^HDMI-|^eDP-|^VGA-' | head -n1 || true)"
  if [ -z "$out" ]; then
    out="$(xrandr --current | awk '/ connected/{print $1; exit}')"
  fi
  echo "$out"
}

apply_auto() {
  local out; out="$(pick_output)"
  if [ -n "$out" ]; then
    log "xrandr --output ${out} --auto"
    xrandr --output "${out}" --auto || true
  else
    log "No connected outputs detected."
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
Description=x-resize (MATE): Xorg RandR auto-resize (user)
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
systemctl --user enable --now mate-x-autoresize.service

echo "OK: enabled user service 'mate-x-autoresize.service'."
echo "Logs: journalctl --user -u mate-x-autoresize -f"
echo "Tip: If it doesn't start at login: loginctl enable-linger $USER"
