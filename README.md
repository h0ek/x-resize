# x-resize
Auto-resize X screen on resolution change.

A script and systemd service that automatically adjusts the X screen resolution when the display size changes, using xrandr and monitoring RANDR events. Ideal for virtual machines or systems with dynamic resolution changes.
I am using it for my Kali machine with XFCE on KVM (virtm-manager).

If you install any Linux system with the XFCE desktop environment in KVM using VirtManager, install spice-agent and qemu-guest-agent, configure everything as it should be and still the screen scaling doesn't work and you almost start crying after hours of Googling and configuration changes you finally come across this repository. Wipe away the tears and sweat, read on and you won't be disappointed.

0. Read the script and understand what it does before you trust me and run it as root on your system xD
1. Download the script:
```wget -O setup-x-resize.sh https://raw.githubusercontent.com/h0ek/x-resize/refs/heads/main/setup-x-resize.sh```
2. Make it executable:
```chmod +x setup-x-resize.sh```
3. Execute as root:
```sudo ./setup-x-resize.sh```

Be happy that your Kali with XFCE auto resize VM with windows :) Ah yeah make sure you select that in View->Scale Display->Auto resize VM with windows
