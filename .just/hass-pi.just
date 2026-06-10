# hass-pi Operations — remote ops via SSH from the dev workstation.
# hass-pi is a Raspberry Pi 5 smart-home / automation node. HDMI gets a TTY for emergencies.
import 'common.just'

set working-directory := ".."

[group("hass-pi")]
ping:
    @ping -c 3 hass-pi.local

[group("hass-pi")]
shell:
    @ssh root@hass-pi.local

[group("hass-pi")]
logs service="home-assistant":
    @ssh root@hass-pi.local "journalctl -u {{service}} -n 50 --no-pager"

# Forward a Wayland app from hass-pi to your local display via SSH.
# The app must be installed on hass-pi. Example: `just hass-pi::gui gnome-disk-utility`
[group("hass-pi")]
gui app:
    @waypipe ssh root@hass-pi.local "{{app}}"
