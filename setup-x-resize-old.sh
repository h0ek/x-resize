#!/bin/bash
# old, first version
# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Get the current user and their home directory
CURRENT_USER=$(logname)
USER_HOME=$(eval echo "~$CURRENT_USER")

# Paths for the service and script
SERVICE_FILE="/etc/systemd/system/x-resize.service"
SCRIPT_FILE="/usr/local/bin/x-resize"

echo "Configuring for user: $CURRENT_USER"

# Create the systemd service file
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Auto resize X screen on resolution change
After=lightdm.service
Requires=lightdm.service

[Service]
ExecStart=$SCRIPT_FILE
ExecStartPre=/bin/sleep 5
User=$CURRENT_USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority
Type=simple
Restart=always

[Install]
WantedBy=graphical.target
EOF

echo "Created systemd service file: $SERVICE_FILE"

# Create the executable script
cat <<'EOF' > "$SCRIPT_FILE"
#!/bin/bash
# Script to listen for RANDR events and automatically adjust the resolution

function x_resize() {
    declare -A disps usrs
    usrs=()
    disps=()

    # Get active users from the 'w' command, skipping 'root'
    for i in $(w -h | awk '{print $1}' | sort | uniq); do
        [[ $i = root ]] && continue  # Skip the root user
        usrs[$i]=1
        echo "Found user: $i"
    done

    # Iterate through users to find active X sessions
    for u in "${!usrs[@]}"; do
        # Check environment variables and X processes
        session_display=$(sudo -u "$u" printenv DISPLAY 2>/dev/null)
        if [[ -n "$session_display" ]]; then
            disps[$session_display]=$u
        fi
    done

    # Listen for resolution changes
    xev -root -event randr | \
    grep --line-buffered 'subtype XRROutputChangeNotifyEvent' | \
    while read foo ; do
        for d in "${!disps[@]}"; do
            session_user="${disps[$d]}"
            session_display="$d"
            session_output=$(sudo -u "$session_user" PATH=/usr/bin DISPLAY="$session_display" xrandr | awk '/ connected/{print $1; exit; }')
            echo "Session User: $session_user"
            echo "Session Display: $session_display"
            echo "Session Output: $session_output"
            sudo -u "$session_user" PATH=/usr/bin DISPLAY="$session_display" xrandr --output "$session_output" --auto
        done
    done
}

# Run the function
x_resize
EOF

# Set appropriate permissions for the script
chmod +x "$SCRIPT_FILE"
echo "Created script: $SCRIPT_FILE"

# Reload systemd configuration, enable the service at startup, and start it
systemctl daemon-reload
systemctl enable x-resize.service
systemctl start x-resize.service

echo "Service has been configured and started."
