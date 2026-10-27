# `my.*` Options Index

> **Auto-generated** by `nix-config/scripts/generate-options-index.py`. Do not edit by hand.
>
> Regenerate with `just maintenance::sync-agent`.

Use this index to find (1) where an option is declared and (2) which hosts / users / presets opt into it. Before editing a module, grep this file for the namespace to see the blast radius.

**Declarations indexed:** 71  
**Consumer files scanned:** 30

---

## `my.android`

### `my.android`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/android.nix:12`
- **Sub-options:** `autoShizuku`, `enable`, `loopbackCam`, `weylus`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

## `my.anythingllmVaultSync`

### `my.anythingllmVaultSync`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/vault-anythingllm-sync.nix:37`
- **Sub-options:** `enable`, `workspaceSlug`
- **Consumed by:** _(no opt-ins detected)_

## `my.attic-push`

### `my.attic-push`

- **Declared:** `nix-presets/attic-push.nix:12`
- **Sub-options:** `enable`, `tokenFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/orin-nano/default.nix`

## `my.atticPull`

### `my.atticPull`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/attic-pull.nix:37`
- **Sub-options:** `cacheHostIp`, `manageHostsEntry`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

## `my.audio`

### `my.audio`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/audio.nix:101`
- **Sub-options:** `jabra.buttons.enable`, `jabra.buttons.smartButtonCommand`, `jabra.preferred`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

## `my.backup`

### `my.backup`

- **Declared:** `nix-presets/nixosModules/backup-engine/default.nix:297`
- **Sub-options:** `bulk.checkOpts`, `bulk.passwordFile`, `bulk.pruneOpts`, `bulk.schedule`, `destinations`, `enable`, `freshness.maxAgeHours`, `freshness.schedule`, `heartbeat.baseUrl`, `heartbeat.pingKeyFile`, `hostName`, `items`, `jobs`, `notify.command`, `secure.agePlugins`, `secure.recipients`, `secure.schedule`, `stateDir`, `warnIfDisabled`
- **Consumed by:** `nix-config.ws/miniflux/hosts/container-factory/default.nix`, `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`, `preset:nix-presets/checks/backup-engine.nix`, `preset:nix-presets/containers/authentik.nix`, `preset:nix-presets/containers/buzz.nix`, `preset:nix-presets/containers/caddy/default.nix`, `preset:nix-presets/containers/caido.nix`, `preset:nix-presets/containers/dev-db.nix`, `preset:nix-presets/containers/ente.nix`, `preset:nix-presets/containers/home-assistant.nix`, `preset:nix-presets/containers/n8n.nix`, `preset:nix-presets/containers/open-webui.nix`, `preset:nix-presets/containers/paperless.nix`, `preset:nix-presets/containers/qbittorrent.nix`, `preset:nix-presets/containers/stalwart.nix`, `preset:nix-presets/containers/vaultwarden.nix`, `preset:nix-presets/nixosModules/backup-engine/default.nix`

## `my.boot`

### `my.boot.initrd-fan`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/initrd-fan.nix:61`
- **Sub-options:** `enable`, `kernelModules`, `pwm`
- **Consumed by:** `nix-config.ws/miniflux/hosts/orin-nano/hardware.nix`

## `my.containers`

### `my.containers.agent-team`

- **Declared:** `nix-presets/containers/agent-team.nix:15`
- **Sub-options:** `agents`, `authorizedKeys`, `autoStart`, `cpuLimit`, `enable`, `hostDataDir`, `ip`, `langfuse.enable`, `langfuse.host`, `langfuse.publicKey`, `langfuse.secretKey`, `litellmUrl`, `manager.humanInTheLoop`, `manager.process`, `memoryLimit`, `secretsFile`
- **Default-enabled** (no hosts import the declaring file)
- **Explicit overrides:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.agent-zero`

- **Declared:** `nix-presets/containers/agent-zero.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.anythingllm`

- **Declared:** `nix-presets/containers/anythingllm.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `llmUrl`, `memoryLimit`, `modelName`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`

### `my.containers.attic`

- **Declared:** `nix-presets/containers/attic.nix:14`
- **Sub-options:** `autoReap.enable`, `autoReap.schedule`, `autoStart`, `enable`, `hostDataDir`, `ip`, `secretsFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.authentik`

- **Declared:** `nix-presets/containers/authentik.nix:52`
- **Sub-options:** `bootstrapAdminPasswordFile`, `bootstrapApiTokenFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `postgresPasswordFile`, `secretKeyFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.backup`

- **Declared:** `nix-presets/containers/backup.nix:12`
- **Sub-options:** `enable`, `ip`, `memoryLimit`, `passwordFile`, `rcloneConfigFile`, `systemPasswordFile`, `systemTargets`, `targets`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.buzz`

- **Declared:** `nix-presets/containers/buzz.nix:60`
- **Sub-options:** `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `hostDataDir`, `ip`, `membership.members`, `membership.ownerPubkey`, `membership.require`, `memoryLimit`, `package`, `pairingRelayUrl`, `relayUrl`, `secretsFile`, `typesenseApiKeyFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.caddy`

- **Declared:** `nix-presets/containers/caddy/default.nix:20`
- **Sub-options:** `enable`, `globalMaintenance`, `hostBridge`, `hostDataDir`, `hostIP`, `ip`, `memoryLimit`, `proxyTargets`, `secretsFile`, `staticSites`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.caido`

- **Declared:** `nix-presets/containers/caido.nix:16`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.code-server`

- **Declared:** `nix-presets/containers/code-server.nix:14`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`, `user`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.comfyui`

- **Declared:** `nix-presets/containers/comfyui.nix:13`
- **Sub-options:** `autoStart`, `enable`, `enableAudio`, `enableGPU`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.crowdsec`

- **Declared:** `nix-presets/containers/crowdsec.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.cups`

- **Declared:** `nix-presets/containers/cups.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.dashboard`

- **Declared:** `nix-presets/containers/dashboard/options.nix:6`
- **Sub-options:** `enable`, `hostBridgeIp`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.dev-db`

- **Declared:** `nix-presets/containers/dev-db.nix:16`
- **Sub-options:** `enable`, `hostDataDir`, `initialDatabases`, `ip`, `memoryLimit`, `postgresPort`, `redisPort`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.ente`

- **Declared:** `nix-presets/containers/ente.nix:24`
- **Sub-options:** `domain`, `enable`, `hostDataDir`, `ip`, `jwtSecretFile`, `keyEncryptionFile`, `keyHashFile`, `memoryLimit`, `minioRootPasswordFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.frigate`

- **Declared:** `nix-presets/containers/frigate.nix:32`
- **Sub-options:** `detector`, `enable`, `enableGPU`, `enableHailo`, `environmentFile`, `hostDataDir`, `innerConfig`, `ip`, `jetson`, `jetsonDevices`, `mediaDir`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.containers.gatus`

- **Declared:** `nix-presets/containers/gatus.nix:32`
- **Sub-options:** `enable`, `endpointsFile`, `ip`, `memoryLimit`, `port`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.hermes`

- **Declared:** `nix-presets/containers/hermes.nix:14`
- **Sub-options:** `discord.enable`, `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`

### `my.containers.home-assistant`

- **Declared:** `nix-presets/containers/home-assistant.nix:14`
- **Sub-options:** `enable`, `enableBluetooth`, `enableUSB`, `hostDataDir`, `ip`, `lanUrl`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/hass-pi/default.nix`

### `my.containers.langflow`

- **Declared:** `nix-presets/containers/langflow.nix:13`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.langfuse`

- **Declared:** `nix-presets/containers/langfuse.nix:17`
- **Sub-options:** `autoStart`, `dbPasswordFile`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.langgraph`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/containers/langgraph.nix:26`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.litellm`

- **Declared:** `nix-presets/containers/litellm.nix:13`
- **Sub-options:** `autoStart`, `backends`, `enable`, `hostDataDir`, `ip`, `masterKeyEnvVar`, `memoryLimit`, `secretsFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.llama-cpp`

- **Declared:** `nix-presets/containers/llama-cpp.nix:24`
- **Sub-options:** `contextSize`, `enable`, `enableCuda`, `gpuLayers`, `ip`, `memoryLimit`, `modelPath`, `port`
- **Consumed by:** `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.containers.loki`

- **Declared:** `nix-presets/containers/loki.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.monitoring`

- **Declared:** `nix-presets/containers/monitoring.nix:20`
- **Sub-options:** `enable`, `githubMetrics.configFile`, `githubMetrics.enable`, `githubMetrics.port`, `githubMetrics.repos`, `githubMetrics.scrapeInterval`, `grafanaOidc.clientId`, `grafanaOidc.clientSecretFile`, `grafanaOidc.enable`, `hostDataDir`, `ip`, `lokiUrl`, `nodeTargets`, `ntfy.authConfigFile`, `ntfy.enable`, `ntfy.topic`, `ntfy.url`, `ollamaTargets`, `vllmTargets`
- **Default-enabled** (no hosts import the declaring file)
- **Explicit overrides:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.n8n`

- **Declared:** `nix-presets/containers/n8n.nix:15`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `noteDirs`, `secretsFile`, `standaloneRunner`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.netdata`

- **Declared:** `nix-presets/containers/netdata.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.nextcloud`

- **Declared:** `nix-presets/containers/nextcloud.nix:14`
- **Sub-options:** `adminPasswordFile`, `dbPasswordFile`, `domain`, `enable`, `enabledApps`, `hostDataDir`, `ip`, `memoryLimit`, `oidcUpstream`
- **Consumed by:** _(no opt-ins detected)_

### `my.containers.ntfy`

- **Declared:** `nix-presets/containers/ntfy.nix:13`
- **Sub-options:** `baseUrl`, `enable`, `ip`, `memoryLimit`, `secretsFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.containers.ollama`

- **Declared:** `nix-presets/containers/ollama.nix:13`
- **Sub-options:** `acceleration`, `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.containers.open-webui`

- **Declared:** `nix-presets/containers/open-webui.nix:20`
- **Sub-options:** `enable`, `enableAudio`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `openaiUrl`, `secretsFile`, `vllmUrl`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.openclaw`

- **Declared:** `nix-presets/containers/openclaw.nix:14`
- **Sub-options:** `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `enableAudio`, `enableUSB`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `vllmUrl`
- **Consumed by:** `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.paperless`

- **Declared:** `nix-presets/containers/paperless.nix:14`
- **Sub-options:** `enable`, `hostConsumptionDir`, `hostDataDir`, `ip`, `memoryLimit`, `passwordFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.persona-runtime`

- **Declared:** `nix-presets/containers/persona-runtime.nix:213`
- **Sub-options:** `autoStart`, `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `gitConfigFile`, `hostDataDir`, `ip`, `memoryLimit`, `personas`, `secretsEnvFile`, `signingKeyFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`

### `my.containers.playground`

- **Declared:** `nix-presets/containers/playground.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `user`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`

### `my.containers.qbittorrent`

- **Declared:** `nix-presets/containers/qbittorrent.nix:16`
- **Sub-options:** `downloadsDir`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `torrentingPort`, `webuiPort`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`

### `my.containers.qdrant`

- **Declared:** `nix-presets/containers/qdrant.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `package`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.containers.stalwart`

- **Declared:** `nix-presets/containers/stalwart.nix:38`
- **Sub-options:** `adminPasswordFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `relaySecretFile`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`

### `my.containers.syncthing`

- **Declared:** `nix-presets/containers/syncthing.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`, `user`, `vaults`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.containers.vaultwarden`

- **Declared:** `nix-presets/containers/vaultwarden.nix:23`
- **Sub-options:** `adminTokenFile`, `domain`, `enable`, `hostDataDir`, `invitationsAllowed`, `ip`, `memoryLimit`, `port`, `signupsAllowed`, `smtp`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

## `my.dataDisk`

### `my.dataDisk`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/data-disk.nix:15`
- **Sub-options:** `cryptName`, `crypttabExtraOpts`, `device`, `enable`, `keyFilePath`, `label`, `mountpoint`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nasbook/data-disk.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

## `my.deploy`

### `my.deploy.autoUpgrade`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/auto-upgrade.nix:50`
- **Sub-options:** `allowReboot`, `cacheUrl`, `dates`, `enable`, `flakeRef`, `hostName`, `maxRuntime`, `ntfy.debounceSec`, `ntfy.enable`, `ntfy.tokenFile`, `ntfy.topicFile`, `ntfy.url`, `randomizedDelaySec`, `requireCache`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/default.nix`

### `my.deploy.comin`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/comin.nix:36`
- **Sub-options:** `branch`, `buildTimeout`, `enable`, `exporter.enable`, `exporter.port`, `hostName`, `pollPeriod`, `requireCache`, `testingBranch`, `url`, `verifySignatures`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`
- **Explicit overrides:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/default.nix`

## `my.desktop`

### `my.desktop`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/desktop.nix:34`
- **Sub-options:** `gnome.enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

### `my.desktop.bottles`

- **Declared:** `nix-presets/nixosModules/bottles.nix:13`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

### `my.desktop.claude`

- **Declared:** `nix-presets/nixosModules/claude.nix:16`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

### `my.desktop.sandboxedApps`

- **Declared:** `nix-presets/nixosModules/sandboxed-apps.nix:22`
- **Sub-options:** `apps`, `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

## `my.hardware`

### `my.hardware.rpi-direct-boot`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/rpi-direct-boot.nix:12`
- **Sub-options:** `enable`
- **Consumed by:** _(no opt-ins detected)_

## `my.heartbeat`

### `my.heartbeat`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/heartbeat.nix:58`
- **Sub-options:** `baseUrl`, `checks`, `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/default.nix`

## `my.herdr-remote-client`

### `my.herdr-remote-client`

- **Declared:** `nix-presets/herdr-remote-client.nix:12`
- **Sub-options:** `enable`, `serverAlias`, `serverIp`, `serverUser`, `shellAlias`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/default.nix`

## `my.hostSecrets`

### `my.hostSecrets`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/host-secrets.nix:13`
- **Sub-options:** `dir`, `initrdSshKey`
- **Consumed by:** _(no opt-ins detected)_

## `my.monitoring`

### `my.monitoring.node`

- **Declared:** `nix-presets/nixosModules/monitoring-node.nix:6`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

## `my.security`

### `my.security.ai-hardening`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/ai-hardening.nix:41`
- **Sub-options:** `airlockIPs`, `enable`, `strictEgress`, `whitelistDomains`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

## `my.services`

### `my.services.cloudflareTunnel`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/cloudflare-tunnel.nix:27`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`

### `my.services.meshLlm`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/mesh-llm.nix:30`
- **Sub-options:** `autoStart`, `enable`, `extraArgs`, `joinTokenSecret`, `meshPort`, `models`, `package`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/ai.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.services.printing`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/printing.nix:14`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/containers.nix`

### `my.services.rpi-eeprom`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/rpi-eeprom.nix:13`
- **Sub-options:** `autoApply`, `enable`, `schedule`
- **Consumed by:** _(no opt-ins detected)_

### `my.services.snapper`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/snapper.nix:12`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

### `my.services.tang`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/tang.nix:11`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/core-pi/default.nix`, `nix-config.ws/miniflux/hosts/hass-pi/default.nix`, `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`, `nix-config.ws/miniflux/hosts/orin-nano/services.nix`

### `my.services.threeDPrinting`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/threed-printing.nix:21`
- **Sub-options:** `enable`
- **Consumed by:** `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

### `my.services.timesync`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/services/timesync.nix:34`
- **Sub-options:** `enable`, `persistentClock.enable`, `persistentClock.path`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`
- **Explicit overrides:** `nix-config.ws/miniflux/hosts/nasbook/default.nix`

## `my.virtualisation`

### `my.virtualisation`

- **Declared:** `nix-config.ws/miniflux/modules/nixos/virtualisation.nix:12`
- **Sub-options:** `enable`, `libvirtd.enable`, `podman.enable`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`
- **Explicit overrides:** `nix-config.ws/miniflux/hosts/mac-mini/default.nix`, `nix-config.ws/miniflux/hosts/nasbook/default.nix`, `nix-config.ws/miniflux/hosts/nixos-nvme/default.nix`

