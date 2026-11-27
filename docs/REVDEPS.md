# Module Reverse Dependencies

> **Auto-generated** by `nix-config/scripts/generate-revdeps-index.py`. Do not edit by hand.
>
> Regenerate with `just dev::sync-agent`.

Which hosts (and home-manager `user@host`s) load each module file, read from the evaluated module graph. Unlike `IMPORTS.md` this includes transitive imports. Grep a path to see who a change reaches. nix-on-droid hosts are not covered.

**Hosts evaluated:** 9  
**Files indexed:** 186

## Inputs → consumers

- `cadre` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `comin` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `disko` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano, orin-nano-bootstrap
- `home-manager` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano; hm: dhirujaan@nixos-nvme, martin@mac-mini, martin@nixos-nvme
- `impermanence` ← hm: dhirujaan@nixos-nvme, martin@mac-mini, martin@nixos-nvme
- `jetpack-nixos` ← orin-nano, orin-nano-bootstrap
- `lanzaboote` ← nixos-nvme
- `nix-app-center` ← nixos-nvme
- `nix-config` ← all hosts; hm: dhirujaan@nixos-nvme, martin@mac-mini, martin@nixos-nvme
- `nix-devshells` ← hm: martin@nixos-nvme
- `nix-flatpak` ← all hosts
- `nix-hardware` ← core-pi, hass-pi, nixos-nvme, orin-nano, orin-nano-bootstrap
- `nix-hardware/nixos-hardware` ← core-pi, hass-pi
- `nix-index-database` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `nix-mineral` ← nixos-nvme, orin-nano
- `nix-omarchy` ← mac-mini, nixos-nvme; hm: dhirujaan@nixos-nvme, martin@nixos-nvme
- `nix-presets` ← container-factory, container-factory-aarch64, core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano; hm: martin@nixos-nvme
- `nixvim` ← hm: martin@nixos-nvme
- `revue` ← nixos-nvme
- `sops-nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano; hm: martin@nixos-nvme

## `cadre`

- `flake.nix#nixosModules.default` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/buzz-agents.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/cadre.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano

## `nix-config`

- `flake.nix#nixosModules.nix-app-center-kept` ← nixos-nvme
- `hosts/container-factory/arm.nix` ← container-factory-aarch64
- `hosts/container-factory/default.nix` ← container-factory, container-factory-aarch64
- `hosts/core-pi/default.nix` ← core-pi
- `hosts/core-pi/foyer-attention.nix` ← core-pi
- `hosts/core-pi/secrets.nix` ← core-pi
- `hosts/hass-pi/default.nix` ← hass-pi
- `hosts/hass-pi/esphome-secrets.nix` ← hass-pi
- `hosts/hass-pi/secrets.nix` ← hass-pi
- `hosts/mac-mini/default.nix` ← mac-mini; hm: martin@mac-mini
- `hosts/mac-mini/disko.nix` ← mac-mini
- `hosts/mac-mini/secrets.nix` ← mac-mini
- `hosts/nasbook/data-disk.nix` ← nasbook
- `hosts/nasbook/default.nix` ← nasbook
- `hosts/nasbook/disko.nix` ← nasbook
- `hosts/nasbook/secrets.nix` ← nasbook
- `hosts/nixos-nvme/ai.nix` ← nixos-nvme
- `hosts/nixos-nvme/caddy-ca-refresh.nix` ← hm: martin@nixos-nvme
- `hosts/nixos-nvme/containers.nix` ← nixos-nvme
- `hosts/nixos-nvme/default.nix` ← nixos-nvme; hm: dhirujaan@nixos-nvme, martin@nixos-nvme
- `hosts/nixos-nvme/disko.nix` ← nixos-nvme
- `hosts/nixos-nvme/garage.nix` ← nixos-nvme
- `hosts/nixos-nvme/hardware-boot.nix` ← nixos-nvme
- `hosts/nixos-nvme/herdr.nix` ← nixos-nvme
- `hosts/nixos-nvme/monitors.nix` ← nixos-nvme; hm: martin@nixos-nvme
- `hosts/nixos-nvme/network.nix` ← nixos-nvme
- `hosts/nixos-nvme/notes-maintenance.nix` ← hm: martin@nixos-nvme
- `hosts/nixos-nvme/secrets.nix` ← nixos-nvme; hm: martin@nixos-nvme
- `hosts/nixos-nvme/ssh-fido-recovery.nix` ← hm: martin@nixos-nvme
- `hosts/orin-nano-bootstrap/default.nix` ← orin-nano-bootstrap
- `hosts/orin-nano-bootstrap/disko.nix` ← orin-nano-bootstrap
- `hosts/orin-nano/default.nix` ← orin-nano
- `hosts/orin-nano/disko.nix` ← orin-nano
- `hosts/orin-nano/hardware.nix` ← orin-nano
- `hosts/orin-nano/network.nix` ← orin-nano
- `hosts/orin-nano/secrets.nix` ← orin-nano
- `hosts/orin-nano/services.nix` ← orin-nano
- `modules/home-manager/ai-agents.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/android.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/default.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/dev.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/gnome.nix` ← hm: martin@mac-mini, martin@nixos-nvme
- `modules/home-manager/nixvim.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/secrets.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/security.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/service-launchers.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/syncthing.nix` ← hm: martin@nixos-nvme
- `modules/home-manager/vscode.nix` ← hm: martin@nixos-nvme
- `modules/nixos/ai-hardening.nix` ← nixos-nvme, orin-nano
- `modules/nixos/ananicy.nix` ← nixos-nvme, orin-nano
- `modules/nixos/android.nix` ← nixos-nvme
- `modules/nixos/apps.nix` ← nixos-nvme
- `modules/nixos/attic-pull.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/audio.nix` ← nixos-nvme
- `modules/nixos/audit.nix` ← nixos-nvme, orin-nano
- `modules/nixos/auto-upgrade.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/backup.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/base.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/claude-code.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/clevis-initrd.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/comin.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/containers/langgraph.nix` ← nixos-nvme
- `modules/nixos/core.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/data-disk.nix` ← nasbook, nixos-nvme
- `modules/nixos/default.nix` ← nixos-nvme
- `modules/nixos/desktop.nix` ← mac-mini, nixos-nvme; hm: martin@nixos-nvme
- `modules/nixos/forward-auth-guard.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/headless.nix` ← core-pi, hass-pi, mac-mini, nasbook, orin-nano
- `modules/nixos/heartbeat.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/host-secrets.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/hosts.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/initrd-fan.nix` ← nixos-nvme, orin-nano
- `modules/nixos/kernel.nix` ← nixos-nvme, orin-nano
- `modules/nixos/machine-id.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/network-routing.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/networking.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/nix-app-center.nix` ← nixos-nvme; hm: martin@nixos-nvme
- `modules/nixos/options.nix` ← container-factory, container-factory-aarch64, core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/persistence.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/pki.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/printing.nix` ← nixos-nvme
- `modules/nixos/pull-deploy-node.nix` ← core-pi, hass-pi, mac-mini, nasbook
- `modules/nixos/rpi-direct-boot.nix` ← core-pi, hass-pi
- `modules/nixos/rpi5-disko.nix` ← core-pi, hass-pi
- `modules/nixos/rpi5-node.nix` ← core-pi, hass-pi
- `modules/nixos/scripts.nix` ← nixos-nvme, orin-nano
- `modules/nixos/security/airlock.nix` ← nixos-nvme
- `modules/nixos/security/clamav.nix` ← nixos-nvme
- `modules/nixos/security/default.nix` ← nixos-nvme
- `modules/nixos/security/hardening.nix` ← nixos-nvme, orin-nano
- `modules/nixos/security/smartcard.nix` ← nixos-nvme
- `modules/nixos/security/ssh.nix` ← nixos-nvme
- `modules/nixos/security/sudo.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/security/sysctl.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/security/usbguard.nix` ← nixos-nvme
- `modules/nixos/services/cadre.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/services/cloudflare-tunnel.nix` ← core-pi
- `modules/nixos/services/github-notify.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/services/langfuse.nix` ← nixos-nvme
- `modules/nixos/services/mesh-llm-gpu-runner.nix` ← core-pi, hass-pi, mac-mini, nasbook, orin-nano
- `modules/nixos/services/rpi-eeprom.nix` ← core-pi, hass-pi
- `modules/nixos/services/tang.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/services/timesync.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/services/vault-anythingllm-sync.nix` ← nixos-nvme
- `modules/nixos/snapper.nix` ← nixos-nvme
- `modules/nixos/threed-printing.nix` ← nixos-nvme
- `modules/nixos/users.nix` ← nixos-nvme, orin-nano
- `modules/nixos/virtualisation.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `modules/nixos/workstation-bundle.nix` ← nixos-nvme
- `modules/nixos/workstation.nix` ← nixos-nvme
- `modules/nixos/zero-trust.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `nix-app-center-home.nix` ← nixos-nvme
- `nix-app-center-system.nix` ← nixos-nvme
- `users/dhirujaan/nixos.nix` ← nixos-nvme
- `users/martin/home.nix` ← hm: martin@nixos-nvme
- `users/martin/nixos.nix` ← mac-mini, nixos-nvme, orin-nano

## `nix-devshells`

- `modules/home-manager.nix` ← hm: martin@nixos-nvme

## `nix-hardware`

- `flake.nix#nixosModules.intel-compute` ← nixos-nvme
- `flake.nix#nixosModules.nixos-nvme` ← nixos-nvme
- `flake.nix#nixosModules.orin-nano` ← orin-nano, orin-nano-bootstrap
- `flake.nix#nixosModules.rpi5` ← core-pi, hass-pi
- `orin-nano.nix` ← orin-nano, orin-nano-bootstrap

## `nix-omarchy`

- `modules/home-manager/default.nix` ← hm: dhirujaan@nixos-nvme, martin@nixos-nvme
- `modules/nixos/default.nix` ← mac-mini, nixos-nvme

## `nix-presets`

- `attic-push.nix` ← nixos-nvme, orin-nano
- `flake.nix#nixosModules.agent-team` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.agent-zero` ← container-factory, container-factory-aarch64, mac-mini
- `flake.nix#nixosModules.all` ← nixos-nvme
- `flake.nix#nixosModules.anythingllm` ← container-factory, container-factory-aarch64, mac-mini
- `flake.nix#nixosModules.attic` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.attic-push` ← orin-nano
- `flake.nix#nixosModules.authentik` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.backup` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.backup-engine` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `flake.nix#nixosModules.buzz` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.caddy` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.caido` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.code-server` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.coderabbit-steward` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.comfyui` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.crowdsec` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.cups` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.dashboard-foyer` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.dev-db` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.ente` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.forgejo` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.frigate` ← container-factory, container-factory-aarch64, orin-nano
- `flake.nix#nixosModules.garage-ui` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.gatus` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.herdr-remote-client` ← core-pi, hass-pi, mac-mini, nasbook, orin-nano
- `flake.nix#nixosModules.hermes` ← container-factory, container-factory-aarch64, mac-mini
- `flake.nix#nixosModules.home-assistant` ← container-factory, container-factory-aarch64, hass-pi
- `flake.nix#nixosModules.langflow` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.langfuse` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.litellm` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.llama-cpp` ← container-factory, container-factory-aarch64, orin-nano
- `flake.nix#nixosModules.loki` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.miniflux` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.monitoring` ← container-factory, container-factory-aarch64, mac-mini, nasbook
- `flake.nix#nixosModules.monitoring-node` ← core-pi, hass-pi, mac-mini, nasbook, orin-nano
- `flake.nix#nixosModules.music-assistant` ← container-factory, container-factory-aarch64, hass-pi
- `flake.nix#nixosModules.n8n` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.netdata` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.ntfy` ← container-factory, container-factory-aarch64, core-pi
- `flake.nix#nixosModules.ollama` ← container-factory, container-factory-aarch64, orin-nano
- `flake.nix#nixosModules.open-webui` ← container-factory, container-factory-aarch64, mac-mini
- `flake.nix#nixosModules.openclaw` ← container-factory, container-factory-aarch64, hass-pi
- `flake.nix#nixosModules.paperless` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.persona-runtime` ← mac-mini
- `flake.nix#nixosModules.photo-frame` ← hass-pi
- `flake.nix#nixosModules.playground` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.qbittorrent` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.qdrant` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.revue` ← container-factory, container-factory-aarch64
- `flake.nix#nixosModules.sandboxed-apps` ← mac-mini
- `flake.nix#nixosModules.stalwart` ← container-factory, container-factory-aarch64, nasbook
- `flake.nix#nixosModules.syncthing` ← container-factory, container-factory-aarch64, nasbook, orin-nano
- `flake.nix#nixosModules.vaultwarden` ← container-factory, container-factory-aarch64, core-pi
- `herdr-remote-client.nix` ← core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `mcp.nix` ← hm: martin@nixos-nvme
- `nixosModules/backup-engine/default.nix` ← container-factory, container-factory-aarch64, core-pi, hass-pi, mac-mini, nasbook, nixos-nvme, orin-nano
- `nixosModules/photo-frame/default.nix` ← hass-pi, nixos-nvme

## `revue`

- `nix/module.nix` ← nixos-nvme

## Unused in nix-config

Files under `modules/nixos/`, `modules/home-manager/` that no evaluated host or user loads: nix-on-droid or colmena-only modules, data files read with a plain `import`, or dead code.

- `modules/home-manager/code-common/settings.nix`
- `modules/nixos/colmena-version-metadata.nix`
- `modules/nixos/keys.nix`
