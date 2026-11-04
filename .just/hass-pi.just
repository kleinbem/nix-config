# hass-pi (Raspberry Pi 5, smart home) ops over SSH from the workstation.
# Uses the `hass-pi` / `hass-pi-initrd` aliases from users/martin/home.nix
# (FIDO2 key + ControlMaster: one PIN+touch per hour). Root login is locked,
# except on the initrd unlock SSH (`just hass-pi::initrd-shell`).
import 'common.just'

set working-directory := ".."

[group("hass-pi")]
ping:
    @ping -c 3 10.0.0.21

[group("hass-pi")]
shell:
    @ssh hass-pi

[group("hass-pi")]
logs service="home-assistant":
    @ssh hass-pi "sudo journalctl -u {{service}} -n 50 --no-pager"

# Forward a Wayland app from hass-pi to your local display via SSH.
# The app must be installed on hass-pi. Example: `just hass-pi::gui gnome-disk-utility`
[group("hass-pi")]
gui app:
    @waypipe ssh hass-pi "{{app}}"

# Open a root shell on the initrd (LUKS unlock stage), port 2222.
[group("hass-pi")]
initrd-shell:
    @ssh hass-pi-initrd
