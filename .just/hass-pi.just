# hass-pi Operations — remote ops via SSH from the dev workstation.
# hass-pi is a Raspberry Pi 5 smart-home / automation node. HDMI gets a TTY for emergencies.
#
# Access notes:
#   - These recipes use the `hass-pi` / `hass-pi-initrd` ssh aliases defined in
#     martin's home-manager ssh config (users/martin/home.nix). Those aliases
#     carry the FIDO2 key, agent bypass, and ControlMaster multiplexing — so the
#     FIRST connection costs one PIN+touch and the rest of the session reuses the
#     master socket with no further touch. Requires `just apply` to have run once
#     so the aliases exist in ~/.ssh/config.
#   - root login is LOCKED on the booted system; we connect as martin + sudo.
#     (root is only used by the initrd SSH on port 2222 for the LUKS unlock,
#     reachable via `just hass-pi::initrd-shell`.)
#   - YubiKey-free access from a machine without a key: `netbird ssh hass-pi`
#     once hass-pi is enrolled in NetBird.
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
