# ESPHome device configs (declarative)

Linked read-only into hass-pi's ESPHome dashboard (`/var/lib/esphome`) by
tmpfiles rules in `../default.nix`, so the dashboard compiles and OTA-updates
them but the source of truth stays in this repo. Secrets (`!secret`) come from sops via `../esphome-secrets.nix`, which
renders the dashboard's `secrets.yaml`: Wi-Fi from kleinbem-secrets
`shared/wifi.yaml` (shared with openwrt-config), `api_key_*` and
`ota_password` from `nix/per-host/hass-pi.yaml` (prefixed `esphome_`). A new
device needs its `esphome_api_key_<name>` there plus a line in `deviceKeys`.

Boards (ESPHome ≥ 2026.8 has first-class support for all of this):

| file | hardware | ESPHome display model |
|------|----------|-----------------------|
| `smart-86-box.yaml` | Waveshare ESP32-P4 Smart 86 Box (4" 720×720 DSI touch, ESP32-C6 Wi-Fi, RJ45, RS485, 2 relays, mic/speaker) | `WAVESHARE-P4-86-PANEL` |

The `# verify` pins in `smart-86-box.yaml` are still from Espressif's reference
design. The HMI 8" panel needs ESPHome `dev` and is built on the workstation:
see `../esphome-dev/hmi-8in/`.
First flash over USB from the `esphome` devshell
(`nix develop ../nix-devshells#esphome`, board shows up as /dev/ttyACM0);
everything after that is OTA from the dashboard.
