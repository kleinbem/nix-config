# NASbook Operations — remote ops via SSH from the dev workstation.
# nasbook is a headless server; HDMI gets a TTY login for emergencies.
import 'common.just'

set working-directory := ".."

[group("NASbook")]
ping:
    @ping -c 3 nasbook.local

[group("NASbook")]
shell:
    @ssh root@nasbook.local

[group("NASbook")]
logs service="paperless":
    @ssh root@nasbook.local "journalctl -u {{service}} -n 50 --no-pager"

# Forward a Wayland app from nasbook to your local display via SSH.
# The app must be installed on nasbook. Example: `just nasbook::gui gnome-disk-utility`
[group("NASbook")]
gui app:
    @waypipe ssh root@nasbook.local "{{app}}"
