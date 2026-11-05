# HMI 8" panel (Waveshare ESP32-P4-WIFI6 8")

Built on the workstation, not by hass-pi's ESPHome dashboard: the config needs
ESPHome `dev` plus the camera PR (esphome/esphome#19480) and a patched
ESP-IDF. `build.sh` pins all three and sets them up in
`${XDG_CACHE_HOME:-~/.cache}/esphome-dev` (`~/.cache` below):

```bash
./build.sh compile
./build.sh upload --device 10.0.0.112     # compile + OTA
./build.sh upload --device /dev/ttyACM0   # compile + USB, if OTA is not possible
./build.sh logs --device 10.0.0.112
```

`secrets.yaml` is read from `~/.cache/esphome-dev/secrets.yaml` (a 0600 copy of
hass-pi's rendered `/var/lib/esphome/secrets.yaml`, or set `SECRETS=`). The guest
Wi-Fi keys are only rendered once `esphome_wifi_guest_ssid` and
`esphome_wifi_guest_password` exist in `nix/per-host/hass-pi.yaml`; until then
add `wifi_guest_ssid`/`wifi_guest_password` to the copy by hand.

Gotchas:

- `idf-5.5.6-ppa-srm-469aa16c.patch` backports espressif/esp-idf#19096: the
  PPA's 90° rotation (LVGL `rotation: 90`) can hang under DSI scanout, and the
  task watchdog then resets the panel (boot loops, failed OTAs). Drop it once
  ESPHome's IDF has the fix.
- `i2s_audio` runs `full_duplex`: mic and speaker share one bus, and without
  it the speaker can't start while the wake word listens. Both stay at 16 kHz.
- The C6 co-processor must run esp-hosted ≥ 3.0 (update entity "C6 firmware"):
  the factory firmware doesn't answer the version RPC, which stalls boot and
  Bluetooth.
- Builds put gcc's temp files in `~/.cache/esphome-dev/tmp`; a small `/tmp`
  tmpfs runs out.
- Logs also go to UART0, the USB-C serial bridge (115200), for crash dumps.
- Radio stations live in `stations.h`; the "Wake-up station" select lists
  their names in the same order. `chime.wav` (16 kHz mono) is built in, so
  the alarm and kitchen timer ring without the internet.
- Hold the Home tab's Light button for the lights pop-up (brightness, colour,
  white, WiZ scenes). The lamps and their names live in `lights.h`.
- The Infra tab shows Gatus (status.kleinbem.dev) once a minute: one tile per
  service, down ones first. The tab button turns red with the number down.
