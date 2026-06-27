# Host Import Graph

> **Auto-generated** by `nix-config/scripts/generate-imports-index.py`. Do not edit by hand.
>
> Regenerate with `just maintenance::sync-agent`.

Top-level imports per host, plus a reverse index. Use this alongside `OPTIONS.md` — that one shows opted-in `my.*` options, this one shows raw module imports (including modules with no `my.*` options).

**Hosts indexed:** 10  
**Distinct imports:** 75

---

## Per host

### `container-factory`

- **Presets:** `nix-presets:agent-team`, `nix-presets:agent-zero`, `nix-presets:anythingllm`, `nix-presets:attic`, `nix-presets:authelia`, `nix-presets:backup`, `nix-presets:caddy`, `nix-presets:code-server`, `nix-presets:comfyui`, `nix-presets:crowdsec`, `nix-presets:cups`, `nix-presets:dashboard`, `nix-presets:frigate`, `nix-presets:github-runner`, `nix-presets:home-assistant`, `nix-presets:langflow`, `nix-presets:langfuse`, `nix-presets:litellm`, `nix-presets:llama-cpp`, `nix-presets:loki`, `nix-presets:monitoring`, `nix-presets:n8n`, `nix-presets:netdata`, `nix-presets:ollama`, `nix-presets:open-webui`, `nix-presets:openclaw`, `nix-presets:paperless`, `nix-presets:playground`, `nix-presets:qdrant`, `nix-presets:syncthing`, `nix-presets:vllm`
- **Local:** `../../modules/nixos/options.nix`

### `core-pi`

- **Modules:** `modules/nixos/rpi5-node.nix`
- **Presets:** `nix-presets:agent-zero`, `nix-presets:anythingllm`, `nix-presets:cups`, `nix-presets:dashboard`, `nix-presets:github-runner`, `nix-presets:ollama`, `nix-presets:open-webui`, `nix-presets:openclaw`
- **Local:** `./disko.nix`

### `hass-pi`

- **Modules:** `modules/nixos/rpi5-node.nix`
- **Presets:** `nix-presets:home-assistant`
- **Local:** `./disko.nix`, `./secrets.nix`

### `nasbook`

- **Modules:** `modules/nixos/base.nix`, `modules/nixos/headless.nix`, `modules/nixos/hosts.nix`
- **Presets:** `nix-presets:agent-team`, `nix-presets:backup`, `nix-presets:loki`, `nix-presets:monitoring`, `nix-presets:paperless`, `nix-presets:qdrant`, `nix-presets:syncthing`
- **Local:** `./hardware-configuration.nix`, `./secrets.nix`

### `nixos-nvme`

- **Modules:** `modules/nixos/apps.nix`, `modules/nixos/data-disk.nix`, `modules/nixos/default.nix`, `modules/nixos/disko.nix`, `modules/nixos/hosts.nix`, `modules/nixos/persistence.nix`, `modules/nixos/services/cloudflare-tunnel.nix`, `modules/nixos/services/container-updater.nix`, `modules/nixos/services/github-runner.nix`, `modules/nixos/snapper.nix`, `modules/nixos/workstation.nix`
- **Presets:** `nix-presets:agent-team`, `nix-presets:agent-zero`, `nix-presets:attic`, `nix-presets:authelia`, `nix-presets:backup`, `nix-presets:caddy`, `nix-presets:claude`, `nix-presets:code-server`, `nix-presets:comfyui`, `nix-presets:container-common`, `nix-presets:crowdsec`, `nix-presets:cups`, `nix-presets:dashboard`, `nix-presets:github-runner`, `nix-presets:langflow`, `nix-presets:langfuse`, `nix-presets:litellm`, `nix-presets:loki`, `nix-presets:monitoring`, `nix-presets:monitoring-node`, `nix-presets:n8n`, `nix-presets:netdata`, `nix-presets:ollama`, `nix-presets:open-webui`, `nix-presets:openclaw`, `nix-presets:paperless`, `nix-presets:playground`, `nix-presets:qdrant`, `nix-presets:syncthing`
- **Hardware:** `nix-hardware:intel-compute`, `nix-hardware:nixos-nvme`
- **Users:** `user:dhirujaan`, `user:martin`
- **Other inputs:** `disko:disko`
- **Local:** `./ai.nix`, `./containers.nix`, `./garage.nix`, `./hardware-boot.nix`, `./network.nix`, `./secrets.nix`, `./specialisations.nix`

### `orin-nano`

- **Modules:** `modules/nixos/ai-hardening.nix`, `modules/nixos/ananicy.nix`, `modules/nixos/audit.nix`, `modules/nixos/base.nix`, `modules/nixos/clevis-initrd.nix`, `modules/nixos/headless.nix`, `modules/nixos/hosts.nix`, `modules/nixos/kernel.nix`, `modules/nixos/persistence.nix`, `modules/nixos/scripts.nix`, `modules/nixos/users.nix`
- **Presets:** `nix-presets:frigate`, `nix-presets:llama-cpp`, `nix-presets:monitoring-node`, `nix-presets:ollama`, `nix-presets:syncthing`
- **Hardware:** `nix-hardware:orin-nano`
- **Users:** `user:martin`
- **Other inputs:** `disko:disko`
- **Local:** `./disko.nix`, `./hardware.nix`, `./network.nix`, `./secrets.nix`, `./services.nix`

### `orin-nano-bootstrap`

- **Hardware:** `nix-hardware:orin-nano`
- **Other inputs:** `disko:disko`
- **Local:** `./disko.nix`

### `phone`

- **Modules:** `modules/nix-on-droid/dashboard.nix`

### `router-1`

- **Modules:** `modules/nixos/base.nix`, `modules/nixos/headless.nix`, `modules/nixos/hosts.nix`
- **Presets:** `nix-presets:monitoring-node`
- **Hardware:** `nix-hardware:lxc-guest`

### `router-2`

- **Modules:** `modules/nixos/base.nix`, `modules/nixos/headless.nix`, `modules/nixos/hosts.nix`
- **Presets:** `nix-presets:monitoring-node`
- **Hardware:** `nix-hardware:lxc-guest`

## Reverse index — import → hosts

- `../../modules/nixos/options.nix` ← container-factory
- `./ai.nix` ← nixos-nvme
- `./containers.nix` ← nixos-nvme
- `./disko.nix` ← core-pi, hass-pi, orin-nano, orin-nano-bootstrap
- `./garage.nix` ← nixos-nvme
- `./hardware-boot.nix` ← nixos-nvme
- `./hardware-configuration.nix` ← nasbook
- `./hardware.nix` ← orin-nano
- `./network.nix` ← nixos-nvme, orin-nano
- `./secrets.nix` ← hass-pi, nasbook, nixos-nvme, orin-nano
- `./services.nix` ← orin-nano
- `./specialisations.nix` ← nixos-nvme
- `disko:disko` ← nixos-nvme, orin-nano, orin-nano-bootstrap
- `modules/nix-on-droid/dashboard.nix` ← phone
- `modules/nixos/ai-hardening.nix` ← orin-nano
- `modules/nixos/ananicy.nix` ← orin-nano
- `modules/nixos/apps.nix` ← nixos-nvme
- `modules/nixos/audit.nix` ← orin-nano
- `modules/nixos/base.nix` ← nasbook, orin-nano, router-1, router-2
- `modules/nixos/clevis-initrd.nix` ← orin-nano
- `modules/nixos/data-disk.nix` ← nixos-nvme
- `modules/nixos/default.nix` ← nixos-nvme
- `modules/nixos/disko.nix` ← nixos-nvme
- `modules/nixos/headless.nix` ← nasbook, orin-nano, router-1, router-2
- `modules/nixos/hosts.nix` ← nasbook, nixos-nvme, orin-nano, router-1, router-2
- `modules/nixos/kernel.nix` ← orin-nano
- `modules/nixos/persistence.nix` ← nixos-nvme, orin-nano
- `modules/nixos/rpi5-node.nix` ← core-pi, hass-pi
- `modules/nixos/scripts.nix` ← orin-nano
- `modules/nixos/services/cloudflare-tunnel.nix` ← nixos-nvme
- `modules/nixos/services/container-updater.nix` ← nixos-nvme
- `modules/nixos/services/github-runner.nix` ← nixos-nvme
- `modules/nixos/snapper.nix` ← nixos-nvme
- `modules/nixos/users.nix` ← orin-nano
- `modules/nixos/workstation.nix` ← nixos-nvme
- `nix-hardware:intel-compute` ← nixos-nvme
- `nix-hardware:lxc-guest` ← router-1, router-2
- `nix-hardware:nixos-nvme` ← nixos-nvme
- `nix-hardware:orin-nano` ← orin-nano, orin-nano-bootstrap
- `nix-presets:agent-team` ← container-factory, nasbook, nixos-nvme
- `nix-presets:agent-zero` ← container-factory, core-pi, nixos-nvme
- `nix-presets:anythingllm` ← container-factory, core-pi
- `nix-presets:attic` ← container-factory, nixos-nvme
- `nix-presets:authelia` ← container-factory, nixos-nvme
- `nix-presets:backup` ← container-factory, nasbook, nixos-nvme
- `nix-presets:caddy` ← container-factory, nixos-nvme
- `nix-presets:claude` ← nixos-nvme
- `nix-presets:code-server` ← container-factory, nixos-nvme
- `nix-presets:comfyui` ← container-factory, nixos-nvme
- `nix-presets:container-common` ← nixos-nvme
- `nix-presets:crowdsec` ← container-factory, nixos-nvme
- `nix-presets:cups` ← container-factory, core-pi, nixos-nvme
- `nix-presets:dashboard` ← container-factory, core-pi, nixos-nvme
- `nix-presets:frigate` ← container-factory, orin-nano
- `nix-presets:github-runner` ← container-factory, core-pi, nixos-nvme
- `nix-presets:home-assistant` ← container-factory, hass-pi
- `nix-presets:langflow` ← container-factory, nixos-nvme
- `nix-presets:langfuse` ← container-factory, nixos-nvme
- `nix-presets:litellm` ← container-factory, nixos-nvme
- `nix-presets:llama-cpp` ← container-factory, orin-nano
- `nix-presets:loki` ← container-factory, nasbook, nixos-nvme
- `nix-presets:monitoring` ← container-factory, nasbook, nixos-nvme
- `nix-presets:monitoring-node` ← nixos-nvme, orin-nano, router-1, router-2
- `nix-presets:n8n` ← container-factory, nixos-nvme
- `nix-presets:netdata` ← container-factory, nixos-nvme
- `nix-presets:ollama` ← container-factory, core-pi, nixos-nvme, orin-nano
- `nix-presets:open-webui` ← container-factory, core-pi, nixos-nvme
- `nix-presets:openclaw` ← container-factory, core-pi, nixos-nvme
- `nix-presets:paperless` ← container-factory, nasbook, nixos-nvme
- `nix-presets:playground` ← container-factory, nixos-nvme
- `nix-presets:qdrant` ← container-factory, nasbook, nixos-nvme
- `nix-presets:syncthing` ← container-factory, nasbook, nixos-nvme, orin-nano
- `nix-presets:vllm` ← container-factory
- `user:dhirujaan` ← nixos-nvme
- `user:martin` ← nixos-nvme, orin-nano
