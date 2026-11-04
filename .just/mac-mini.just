# mac-mini day-to-day ops over SSH; provisioning lives in deployment.just.
# Uses the static IP: mac-mini.local's mDNS lookup hangs from the workstation.
# No `gui` recipe: it has a full GNOME session over RDP
# (deployment::mac-mini-verify prints the tunnel command).
import 'common.just'

set working-directory := ".."

[group("mac-mini")]
ping:
    @ping -c 3 10.0.0.16

[group("mac-mini")]
shell:
    @ssh martin@10.0.0.16

[group("mac-mini")]
logs service="gnome-remote-desktop":
    @ssh martin@10.0.0.16 "journalctl -u {{service}} -n 50 --no-pager"
