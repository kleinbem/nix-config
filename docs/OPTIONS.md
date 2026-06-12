# `my.*` Options Index

> **Auto-generated** by `nix-config/scripts/generate-options-index.py`. Do not edit by hand.
>
> Regenerate with `just maintenance::sync-agent`.

Use this index to find (1) where an option is declared and (2) which hosts / users / presets opt into it. Before editing a module, grep this file for the namespace to see the blast radius.

**Declarations indexed:** 42  
**Consumer files scanned:** 13

---

## `my.android`

### `my.android`

- **Declared:** `nix-config/modules/nixos/android.nix:12`
- **Sub-options:** `enable`
- **Consumed by:** `host:nixos-nvme`

## `my.containers`

### `my.containers.agent-team`

- **Declared:** `nix-presets/containers/agent-team.nix:15`
- **Sub-options:** `agents`, `autoStart`, `cpuLimit`, `enable`, `hostDataDir`, `ip`, `langfuse.enable`, `langfuse.host`, `langfuse.publicKey`, `langfuse.secretKey`, `litellmUrl`, `manager.humanInTheLoop`, `manager.process`, `memoryLimit`, `secretsFile`
- **Default-enabled** (no hosts import the declaring file)
- **Explicit overrides:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.agent-zero`

- **Declared:** `nix-presets/containers/agent-zero.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.anythingllm`

- **Declared:** `nix-presets/containers/anythingllm.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `llmUrl`, `memoryLimit`, `modelName`
- **Consumed by:** `host:container-factory`, `host:core-pi`

### `my.containers.attic`

- **Declared:** `nix-presets/containers/attic.nix:13`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `secretsFile`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.authelia`

- **Declared:** `nix-presets/containers/authelia.nix:14`
- **Sub-options:** `domain`, `enable`, `hostDataDir`, `ip`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.backup`

- **Declared:** `nix-presets/containers/backup.nix:12`
- **Sub-options:** `enable`, `ip`, `memoryLimit`, `passwordFile`, `rcloneConfigFile`, `systemPasswordFile`, `systemTargets`, `targets`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.caddy`

- **Declared:** `nix-presets/containers/caddy/default.nix:18`
- **Sub-options:** `enable`, `hostBridge`, `hostDataDir`, `hostIP`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.code-server`

- **Declared:** `nix-presets/containers/code-server.nix:14`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`, `user`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.comfyui`

- **Declared:** `nix-presets/containers/comfyui.nix:12`
- **Sub-options:** `autoStart`, `enable`, `enableAudio`, `enableGPU`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.crowdsec`

- **Declared:** `nix-presets/containers/crowdsec.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.cups`

- **Declared:** `nix-presets/containers/cups.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.dashboard`

- **Declared:** `nix-presets/containers/dashboard/options.nix:6`
- **Sub-options:** `enable`, `hostBridgeIp`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.frigate`

- **Declared:** `nix-presets/containers/frigate.nix:12`
- **Sub-options:** `detector`, `enable`, `enableGPU`, `enableHailo`, `hostDataDir`, `innerConfig`, `ip`, `mediaDir`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:orin-nano`

### `my.containers.github-runner`

- **Declared:** `nix-presets/containers/github-runner.nix:42`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.home-assistant`

- **Declared:** `nix-presets/containers/home-assistant.nix:12`
- **Sub-options:** `enable`, `enableBluetooth`, `enableUSB`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:hass-pi`

### `my.containers.langflow`

- **Declared:** `nix-presets/containers/langflow.nix:12`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.langfuse`

- **Declared:** `nix-presets/containers/langfuse.nix:13`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.litellm`

- **Declared:** `nix-presets/containers/litellm.nix:13`
- **Sub-options:** `autoStart`, `backends`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.llama-cpp`

- **Declared:** `nix-presets/containers/llama-cpp.nix:20`
- **Sub-options:** `contextSize`, `enable`, `gpuLayers`, `ip`, `memoryLimit`, `modelPath`
- **Consumed by:** `host:container-factory`, `host:orin-nano`

### `my.containers.loki`

- **Declared:** `nix-presets/containers/loki.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.monitoring`

- **Declared:** `nix-presets/containers/monitoring.nix:13`
- **Sub-options:** `enable`, `githubMetrics.configFile`, `githubMetrics.enable`, `githubMetrics.port`, `githubMetrics.repos`, `githubMetrics.scrapeInterval`, `hostDataDir`, `ip`, `nodeTargets`, `ollamaTargets`, `vllmTargets`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.n8n`

- **Declared:** `nix-presets/containers/n8n.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `noteDirs`, `secretsFile`, `standaloneRunner`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.netdata`

- **Declared:** `nix-presets/containers/netdata.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.ollama`

- **Declared:** `nix-presets/containers/ollama.nix:13`
- **Sub-options:** `acceleration`, `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`, `host:orin-nano`

### `my.containers.open-webui`

- **Declared:** `nix-presets/containers/open-webui.nix:14`
- **Sub-options:** `enable`, `enableAudio`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.openclaw`

- **Declared:** `nix-presets/containers/openclaw.nix:13`
- **Sub-options:** `enable`, `enableAudio`, `enableUSB`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `vllmUrl`
- **Consumed by:** `host:container-factory`, `host:core-pi`, `host:nixos-nvme`

### `my.containers.paperless`

- **Declared:** `nix-presets/containers/paperless.nix:12`
- **Sub-options:** `enable`, `hostConsumptionDir`, `hostDataDir`, `ip`, `memoryLimit`, `passwordFile`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.playground`

- **Declared:** `nix-presets/containers/playground.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `user`
- **Consumed by:** `host:container-factory`, `host:nixos-nvme`

### `my.containers.qdrant`

- **Declared:** `nix-presets/containers/qdrant.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.syncthing`

- **Declared:** `nix-presets/containers/syncthing.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`, `user`, `vaults`
- **Consumed by:** `host:container-factory`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.containers.vllm`

- **Declared:** `nix-presets/containers/vllm.nix:12`
- **Sub-options:** `autoStart`, `device`, `enable`, `enableAudio`, `enableGPU`, `enforceEager`, `extraArgs`, `gpuMemoryUtilization`, `hostDataDir`, `image`, `ip`, `maxModelLen`, `memoryLimit`, `memorySwapMax`, `model`, `openvinoDevice`, `openvinoKvCacheSpace`, `quantization`, `secretsFile`
- **Consumed by:** `host:container-factory`

## `my.desktop`

### `my.desktop`

- **Declared:** `nix-config/modules/nixos/desktop.nix:12`
- **Sub-options:** `gnome.enable`
- **Consumed by:** `host:nixos-nvme`

## `my.hardware`

### `my.hardware.rpi-direct-boot`

- **Declared:** `nix-config/modules/nixos/rpi-direct-boot.nix:12`
- **Sub-options:** `enable`
- **Consumed by:** _(no opt-ins detected)_

## `my.monitoring`

### `my.monitoring.node`

- **Declared:** `nix-presets/nixosModules/monitoring-node.nix:6`
- **Sub-options:** `enable`
- **Consumed by:** `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`, `host:router-1`, `host:router-2`

## `my.security`

### `my.security.ai-hardening`

- **Declared:** `nix-config/modules/nixos/ai-hardening.nix:12`
- **Sub-options:** `airlockIPs`, `enable`, `strictEgress`, `whitelistDomains`
- **Consumed by:** `host:nixos-nvme`, `host:orin-nano`

## `my.services`

### `my.services.container-updater`

- **Declared:** `nix-config/modules/nixos/services/container-updater.nix:11`
- **Sub-options:** `containers`, `enable`, `flakeURI`
- **Consumed by:** `host:nixos-nvme`

### `my.services.printing`

- **Declared:** `nix-config/modules/nixos/printing.nix:16`
- **Sub-options:** `enable`
- **Consumed by:** `host:nixos-nvme`

### `my.services.rpi-eeprom`

- **Declared:** `nix-config/modules/nixos/services/rpi-eeprom.nix:13`
- **Sub-options:** `autoApply`, `enable`, `schedule`
- **Consumed by:** `host:core-pi`, `host:hass-pi`

### `my.services.tang`

- **Declared:** `nix-config/modules/nixos/services/tang.nix:11`
- **Sub-options:** `enable`
- **Consumed by:** `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.services.timesync`

- **Declared:** `nix-config/modules/nixos/services/timesync.nix:11`
- **Sub-options:** `enable`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`, `host:router-1`, `host:router-2`
- **Explicit overrides:** `host:router-1`, `host:router-2`

## `my.virtualisation`

### `my.virtualisation`

- **Declared:** `nix-config/modules/nixos/virtualisation.nix:12`
- **Sub-options:** `enable`, `libvirtd.enable`, `lxc.enable`, `podman.enable`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`, `host:router-1`, `host:router-2`
- **Explicit overrides:** `host:core-pi`, `host:hass-pi`, `host:nixos-nvme`

