# core-pi Operations — remote ops via SSH from the dev workstation.
# core-pi is a Raspberry Pi 5 AI / infra node. HDMI gets a TTY for emergencies.
import 'common.just'

set working-directory := ".."

[group("core-pi")]
ping:
    @ping -c 3 core-pi.local

[group("core-pi")]
shell:
    @ssh root@core-pi.local

[group("core-pi")]
logs service="ollama":
    @ssh root@core-pi.local "journalctl -u {{service}} -n 50 --no-pager"

# Forward a Wayland app from core-pi to your local display via SSH.
# The app must be installed on core-pi. Example: `just core-pi::gui gnome-disk-utility`
[group("core-pi")]
gui app:
    @waypipe ssh root@core-pi.local "{{app}}"
