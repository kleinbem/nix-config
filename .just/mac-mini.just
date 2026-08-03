# mac-mini Operations — remote ops via SSH from the dev workstation.
# mac-mini is a headless GNOME desktop box (GDM autologin, GNOME Remote
# Desktop for GUI access) — no physical keyboard/screen/HDMI TTY, ever.
#
# mac-mini.local doesn't reliably resolve from this workstation (mDNS lookup
# just hangs) — these recipes use the static IP (inventory.nix) directly
# instead of the .local pattern core-pi/nasbook use.
#
# No `gui` recipe here, unlike the other per-host justfiles: those hosts are
# pure headless with no desktop environment at all, so forwarding one app via
# waypipe is their only way to see a GUI. mac-mini already has a full GNOME
# session reachable over RDP (see deployment::mac-mini-verify's output for
# the tunnel command) — waypipe-ing a single app in addition would be
# redundant, not an accidental gap.
#
# Provisioning-shaped operations (install/update the SSD, verify a fresh
# boot, wake from sleep) live in deployment.just instead of here — this file
# is just the lightweight day-to-day CLI layer.
import 'common.just'

set working-directory := ".."

[group("mac-mini")]
ping:
    @ping -c 3 10.0.0.16

[group("mac-mini")]
shell:
    @ssh root@10.0.0.16

[group("mac-mini")]
logs service="gnome-remote-desktop-headless":
    @ssh martin@10.0.0.16 "journalctl --user -u {{service}} -n 50 --no-pager"
