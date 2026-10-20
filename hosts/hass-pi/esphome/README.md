# ESPHome device configs (declarative)

Linked read-only into hass-pi's ESPHome dashboard (`/var/lib/esphome`) by
tmpfiles rules in `../default.nix`, so the dashboard compiles and OTA-updates
them but the source of truth stays in this repo. Secrets (`!secret`) come from
the dashboard's own `secrets.yaml`, which is state, not config: fill
`wifi_ssid`, `wifi_password`, `api_key_*`, `ota_password` there once.

Boards (ESPHome ≥ 2026.8 has first-class support for all of this):

| file | hardware | ESPHome display model |
|------|----------|-----------------------|
| `smart-86-box.yaml` | Waveshare ESP32-P4 Smart 86 Box (4" 720×720 DSI touch, ESP32-C6 Wi-Fi, RJ45, RS485, 2 relays, mic/speaker) | `WAVESHARE-P4-86-PANEL` |
| `hmi-8in.yaml` | Waveshare ESP32-P4-WIFI6 8" HMI (800×1280 DSI 10-point touch, dual mic, speaker) | `WAVESHARE-8-DSI-TOUCH-A` |

Pin assignments marked `# verify` were taken from Espressif's ESP32-P4
reference design (ESPHome's own esp32_hosted test config); check them against
the Waveshare wiki page of each board before the first flash:
https://www.waveshare.com/wiki/ESP32-P4-86-Panel-ETH-2RO and
https://www.waveshare.com/wiki/ESP32-P4-WIFI6-Touch-LCD-8 (adjust if the
product page differs). First flash over USB from the `esphome` devshell
(`nix develop ../nix-devshells#esphome`, board shows up as /dev/ttyACM0);
everything after that is OTA from the dashboard.
