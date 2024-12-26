# x-resize
Auto-resize X screen on resolution change.

A script and systemd service that automatically adjusts the X screen resolution when the display size changes, using xrandr and monitoring RANDR events. Ideal for virtual machines or systems with dynamic resolution changes.
I am using it for my Kali machine with XFCE on KVM (virt-manager).

If you install any Linux system with the XFCE desktop environment in KVM using VirtManager, install spice-agent and qemu-guest-agent, configure everything as it should be and still the screen scaling doesn't work and you almost start crying after hours of Googling and configuration changes you finally come across this repository. Wipe away the tears and sweat, read on and you won't be disappointed.

0. Read the script and understand what it does before you trust me and run it as root on your system xD
1. Download the script:
```
wget -O setup-x-resize.sh https://raw.githubusercontent.com/h0ek/x-resize/refs/heads/main/setup-x-resize.sh
```
3. Make it executable:
```
chmod +x setup-x-resize.sh
```
5. Execute as root:
```
sudo ./setup-x-resize.sh
```

Be happy that your Kali with XFCE auto resize VM with windows :) Ah yeah make sure you select that in `View->Scale Display->Auto resize VM with windows` in your Virt-Manager

The solution is based on modifying and adapting what other people smarter than me have come up with:
- https://superuser.com/questions/1183834/no-auto-resize-with-spice-and-virt-manager
- https://unix.stackexchange.com/questions/117083/how-to-get-the-list-of-all-active-x-sessions-and-owners-of-them
- https://gitlab.freedesktop.org/xorg/app/xrandr/-/issues/71
- https://unix.stackexchange.com/questions/614027/how-to-enable-automatic-change-of-guest-resolution-to-fit-boxes-window
- https://nodal-notebook.aria-network.com/technical_advice/auto-adjusting-screen-resolutions-kvm-qemu-udev-spice/
- https://gitlab.xfce.org/xfce/xfce4-settings/-/issues/142
- https://gitlab.com/apteryks/x-resize

Tested on:
Kali GNU/Linux Rolling, release 2024.4, kernel 6.11.2-amd64, desktop environment Xfce 4.20
