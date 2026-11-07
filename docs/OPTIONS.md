# `my.*` Options Index

> **Auto-generated** by `nix-config/scripts/generate-options-index.py`. Do not edit by hand.
>
> Regenerate with `just dev::sync-agent`.

Use this index to find (1) where an option is declared and (2) which hosts / users / presets set it (any value, `enable = false` included). Before editing a module, grep this file for the namespace to see the blast radius.

**Declarations indexed:** 79  
**Consumer files scanned:** 37

---

## `my.android`

### `my.android`

- **Declared:** `nix-config/modules/nixos/android.nix:12`
- **Sub-options:** `autoShizuku`, `enable`, `loopbackCam`, `weylus`
- **Configured in:** `host:nixos-nvme`

## `my.anythingllmVaultSync`

### `my.anythingllmVaultSync`

- **Declared:** `nix-config/modules/nixos/services/vault-anythingllm-sync.nix:24`
- **Sub-options:** `enable`, `workspaceSlug`
- **Configured in:** _(not set anywhere)_

## `my.attic-push`

### `my.attic-push`

- **Declared:** `nix-presets/attic-push.nix:12`
- **Sub-options:** `enable`, `tokenFile`
- **Configured in:** `host:orin-nano`

## `my.atticPull`

### `my.atticPull`

- **Declared:** `nix-config/modules/nixos/attic-pull.nix:17`
- **Sub-options:** `cacheHostIp`, `manageHostsEntry`
- **Configured in:** `host:core-pi`

## `my.audio`

### `my.audio`

- **Declared:** `nix-config/modules/nixos/audio.nix:101`
- **Sub-options:** `jabra.buttons.enable`, `jabra.buttons.smartButtonCommand`, `jabra.preferred`
- **Configured in:** `host:nixos-nvme`

## `my.backup`

### `my.backup`

- **Declared:** `nix-presets/nixosModules/backup-engine/default.nix:304`
- **Sub-options:** `bulk.checkOpts`, `bulk.passwordFile`, `bulk.pruneOpts`, `bulk.schedule`, `destinations`, `enable`, `freshness.maxAgeHours`, `freshness.schedule`, `heartbeat.baseUrl`, `heartbeat.pingKeyFile`, `hostName`, `items`, `jobs`, `notify.command`, `secure.agePlugins`, `secure.recipients`, `secure.schedule`, `stateDir`, `warnIfDisabled`
- **Configured in:** `host:container-factory`, `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`, `preset:nix-presets/checks/backup-engine.nix`, `preset:nix-presets/containers/authentik.nix`, `preset:nix-presets/containers/buzz.nix`, `preset:nix-presets/containers/caddy/default.nix`, `preset:nix-presets/containers/caido.nix`, `preset:nix-presets/containers/dev-db.nix`, `preset:nix-presets/containers/ente.nix`, `preset:nix-presets/containers/forgejo.nix`, `preset:nix-presets/containers/home-assistant.nix`, `preset:nix-presets/containers/miniflux.nix`, `preset:nix-presets/containers/music-assistant.nix`, `preset:nix-presets/containers/n8n.nix`, `preset:nix-presets/containers/open-webui.nix`, `preset:nix-presets/containers/paperless.nix`, `preset:nix-presets/containers/qbittorrent.nix`, `preset:nix-presets/containers/revue.nix`, `preset:nix-presets/containers/stalwart.nix`, `preset:nix-presets/containers/vaultwarden.nix`, `preset:nix-presets/nixosModules/backup-engine/default.nix`, `preset:nix-presets/nixosModules/photo-frame/default.nix`

## `my.boot`

### `my.boot.clevis-initrd`

- **Declared:** `nix-config/modules/nixos/clevis-initrd.nix:64`
- **Sub-options:** `enable`, `fallbackMessage`, `hostIp`, `luksDevice`, `networkInterface`, `secretFile`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.boot.initrd-fan`

- **Declared:** `nix-config/modules/nixos/initrd-fan.nix:61`
- **Sub-options:** `enable`, `kernelModules`, `pwm`
- **Configured in:** `host:orin-nano`

## `my.claudeCode`

### `my.claudeCode`

- **Declared:** `nix-config/modules/nixos/claude-code.nix:16`
- **Sub-options:** `enable`, `settings`
- **Configured in:** `host:nixos-nvme`

## `my.containers`

### `my.containers.agent-zero`

- **Declared:** `nix-presets/containers/agent-zero.nix:84`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `modelPreset`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Configured in:** `host:mac-mini`, `host:nixos-nvme`

### `my.containers.anythingllm`

- **Declared:** `nix-presets/containers/anythingllm.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `llmUrl`, `memoryLimit`, `modelName`
- **Configured in:** `host:mac-mini`

### `my.containers.attic`

- **Declared:** `nix-presets/containers/attic.nix:14`
- **Sub-options:** `autoReap.enable`, `autoReap.schedule`, `autoStart`, `enable`, `hostDataDir`, `ip`, `secretsFile`, `upstreamCacheKeyNames`
- **Configured in:** `host:core-pi`

### `my.containers.authentik`

- **Declared:** `nix-presets/containers/authentik.nix:28`
- **Sub-options:** `bootstrapAdminPasswordFile`, `bootstrapApiTokenFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `postgresPasswordFile`, `secretKeyFile`
- **Configured in:** `host:core-pi`

### `my.containers.backup`

- **Declared:** `nix-presets/containers/backup.nix:12`
- **Sub-options:** `enable`, `ip`, `memoryLimit`, `passwordFile`, `rcloneConfigFile`, `systemPasswordFile`, `systemTargets`, `targets`
- **Configured in:** `host:nixos-nvme`

### `my.containers.buzz`

- **Declared:** `nix-presets/containers/buzz.nix:41`
- **Sub-options:** `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `hostDataDir`, `ip`, `membership.members`, `membership.ownerPubkey`, `membership.require`, `memoryLimit`, `package`, `pairingRelayUrl`, `relayUrl`, `secretsFile`, `typesenseApiKeyFile`
- **Configured in:** `host:nixos-nvme`

### `my.containers.caddy`

- **Declared:** `nix-presets/containers/caddy/default.nix:20`
- **Sub-options:** `authUpstream`, `enable`, `globalMaintenance`, `hostBridge`, `hostDataDir`, `hostIP`, `ip`, `memoryLimit`, `proxyTargets`, `secretsFile`, `staticSites`
- **Configured in:** `host:core-pi`, `host:nixos-nvme`

### `my.containers.caido`

- **Declared:** `nix-presets/containers/caido.nix:16`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`
- **Configured in:** `host:nixos-nvme`

### `my.containers.code-server`

- **Declared:** `nix-presets/containers/code-server.nix:14`
- **Sub-options:** `allowedSources`, `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`, `user`
- **Configured in:** `host:nixos-nvme`

### `my.containers.comfyui`

- **Declared:** `nix-presets/containers/comfyui.nix:13`
- **Sub-options:** `autoStart`, `enable`, `enableAudio`, `enableGPU`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`
- **Configured in:** `host:nixos-nvme`

### `my.containers.crowdsec`

- **Declared:** `nix-presets/containers/crowdsec.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Configured in:** `host:core-pi`

### `my.containers.cups`

- **Declared:** `nix-presets/containers/cups.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `privateUsers`
- **Configured in:** `host:core-pi`, `host:nixos-nvme`

### `my.containers.dashboard`

- **Declared:** `nix-presets/containers/dashboard/options.nix:6`
- **Sub-options:** `enable`, `hostBridgeIp`, `ip`, `memoryLimit`, `secretsFile`
- **Configured in:** `host:core-pi`

### `my.containers.dev-db`

- **Declared:** `nix-presets/containers/dev-db.nix:16`
- **Sub-options:** `allowedClients`, `enable`, `hostDataDir`, `initialDatabases`, `ip`, `memoryLimit`, `postgresPort`, `redisPort`
- **Configured in:** `host:nixos-nvme`

### `my.containers.ente`

- **Declared:** `nix-presets/containers/ente.nix:33`
- **Sub-options:** `domain`, `enable`, `garage.capacity`, `garage.enable`, `garage.memoryMax`, `garage.rpcSecretFile`, `hostDataDir`, `ip`, `jwtSecretFile`, `keyEncryptionFile`, `keyHashFile`, `memoryLimit`, `minio.enable`, `minioRootPasswordFile`, `s3.accessKeyIdFile`, `s3.backend`, `s3.bucket`, `s3.secretAccessKeyFile`
- **Configured in:** `host:core-pi`

### `my.containers.forgejo`

- **Declared:** `nix-presets/containers/forgejo.nix:27`
- **Sub-options:** `actions.enable`, `admin.email`, `admin.name`, `admin.passwordFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`, `ssh.enable`, `ssh.port`
- **Configured in:** `host:mac-mini`, `preset:nix-presets/checks/forgejo.nix`

### `my.containers.frigate`

- **Declared:** `nix-presets/containers/frigate.nix:32`
- **Sub-options:** `detector`, `enable`, `enableGPU`, `enableHailo`, `environmentFile`, `hostDataDir`, `innerConfig`, `ip`, `jetson`, `jetsonDevices`, `mediaDir`, `memoryLimit`
- **Configured in:** `host:orin-nano`

### `my.containers.garage-ui`

- **Declared:** `nix-presets/containers/garage-ui.nix:104`
- **Sub-options:** `adminPort`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`, `region`, `rootUrl`, `s3Port`, `secretsFile`, `tokenLogin`
- **Configured in:** `host:nixos-nvme`

### `my.containers.gatus`

- **Declared:** `nix-presets/containers/gatus.nix:74`
- **Sub-options:** `alerting.fallback.priority`, `alerting.fallback.topicFile`, `alerting.fallback.url`, `alerting.ntfy.priority`, `alerting.ntfy.tokenFile`, `alerting.ntfy.topicFile`, `alerting.ntfy.url`, `enable`, `endpointsFile`, `ip`, `memoryLimit`, `port`
- **Configured in:** `host:core-pi`

### `my.containers.github-runner`

- **Declared:** `nix-presets/containers/github-runner.nix:82`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `runners`, `secretsFile`
- **Configured in:** `host:nixos-nvme`

### `my.containers.hermes`

- **Declared:** `nix-presets/containers/hermes.nix:14`
- **Sub-options:** `discord.enable`, `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `secretsFile`, `vllmUrl`
- **Configured in:** `host:mac-mini`

### `my.containers.home-assistant`

- **Declared:** `nix-presets/containers/home-assistant.nix:14`
- **Sub-options:** `enable`, `enableBluetooth`, `enableUSB`, `hostDataDir`, `ip`, `lanUrl`, `memoryLimit`
- **Configured in:** `host:hass-pi`

### `my.containers.langflow`

- **Declared:** `nix-presets/containers/langflow.nix:13`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Configured in:** `host:nixos-nvme`

### `my.containers.langfuse`

- **Declared:** `nix-presets/containers/langfuse.nix:17`
- **Sub-options:** `autoStart`, `dbPasswordFile`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`
- **Configured in:** `host:nixos-nvme`

### `my.containers.langgraph`

- **Declared:** `nix-config/modules/nixos/containers/langgraph.nix:26`
- **Sub-options:** `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `port`
- **Configured in:** `host:nixos-nvme`

### `my.containers.litellm`

- **Declared:** `nix-presets/containers/litellm.nix:13`
- **Sub-options:** `autoStart`, `backends`, `enable`, `hostDataDir`, `ip`, `masterKeyEnvVar`, `memoryLimit`, `secretsFile`
- **Configured in:** `host:nixos-nvme`

### `my.containers.llama-cpp`

- **Declared:** `nix-presets/containers/llama-cpp.nix:41`
- **Sub-options:** `contextSize`, `enable`, `enableCuda`, `gpuLayers`, `ip`, `memoryLimit`, `modelPath`, `port`
- **Configured in:** `host:orin-nano`

### `my.containers.loki`

- **Declared:** `nix-presets/containers/loki.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Configured in:** `host:nasbook`, `host:nixos-nvme`

### `my.containers.miniflux`

- **Declared:** `nix-presets/containers/miniflux.nix:23`
- **Sub-options:** `adminCredentialsFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `pollingFrequency`, `port`
- **Configured in:** `host:nasbook`

### `my.containers.monitoring`

- **Declared:** `nix-presets/containers/monitoring.nix:16`
- **Sub-options:** `enable`, `githubMetrics.configFile`, `githubMetrics.enable`, `githubMetrics.port`, `githubMetrics.repos`, `githubMetrics.scrapeInterval`, `grafanaEnvFile`, `grafanaOidc.clientId`, `grafanaOidc.clientSecretFile`, `grafanaOidc.enable`, `hostDataDir`, `ip`, `lokiUrl`, `nodeTargets`, `ntfy.authConfigFile`, `ntfy.enable`, `ntfy.topic`, `ntfy.url`, `ollamaTargets`, `vllmTargets`
- **Configured in:** `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`

### `my.containers.music-assistant`

- **Declared:** `nix-presets/containers/music-assistant.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `mediaDir`, `memoryLimit`, `providers`
- **Configured in:** `host:hass-pi`

### `my.containers.n8n`

- **Declared:** `nix-presets/containers/n8n.nix:15`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `noteDirs`, `secretsFile`, `standaloneRunner`
- **Configured in:** `host:nixos-nvme`

### `my.containers.netdata`

- **Declared:** `nix-presets/containers/netdata.nix:13`
- **Sub-options:** `enable`, `hostDataDir`, `ip`
- **Configured in:** `host:nixos-nvme`

### `my.containers.nextcloud`

- **Declared:** `nix-presets/containers/nextcloud.nix:14`
- **Sub-options:** `adminPasswordFile`, `dbPasswordFile`, `domain`, `enable`, `enabledApps`, `hostDataDir`, `ip`, `memoryLimit`, `oidcUpstream`
- **Configured in:** _(not set anywhere)_

### `my.containers.ntfy`

- **Declared:** `nix-presets/containers/ntfy.nix:13`
- **Sub-options:** `baseUrl`, `enable`, `ip`, `memoryLimit`, `secretsFile`
- **Configured in:** `host:core-pi`

### `my.containers.ollama`

- **Declared:** `nix-presets/containers/ollama.nix:13`
- **Sub-options:** `acceleration`, `autoStart`, `enable`, `hostDataDir`, `ip`, `memoryLimit`
- **Configured in:** `host:nixos-nvme`, `host:orin-nano`

### `my.containers.open-webui`

- **Declared:** `nix-presets/containers/open-webui.nix:20`
- **Sub-options:** `enable`, `enableAudio`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `openaiUrl`, `secretsFile`, `vllmUrl`
- **Configured in:** `host:mac-mini`, `host:nixos-nvme`

### `my.containers.openclaw`

- **Declared:** `nix-presets/containers/openclaw.nix:14`
- **Sub-options:** `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `enableAudio`, `enableUSB`, `enableVideo`, `hostDataDir`, `ip`, `memoryLimit`, `ollamaUrl`, `vllmUrl`
- **Configured in:** `host:hass-pi`, `host:nixos-nvme`

### `my.containers.paperless`

- **Declared:** `nix-presets/containers/paperless.nix:14`
- **Sub-options:** `enable`, `hostConsumptionDir`, `hostDataDir`, `ip`, `memoryLimit`, `passwordFile`
- **Configured in:** `host:nasbook`, `host:nixos-nvme`

### `my.containers.persona-runtime`

- **Declared:** `nix-presets/containers/persona-runtime.nix:155`
- **Sub-options:** `autoStart`, `egress.lanAllowlist`, `egress.restrictLan`, `enable`, `gitConfigFile`, `hostDataDir`, `ip`, `memoryLimit`, `personas`, `secretsEnvFile`, `signingKeyFile`
- **Configured in:** `host:mac-mini`

### `my.containers.playground`

- **Declared:** `nix-presets/containers/playground.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `user`
- **Configured in:** `host:nixos-nvme`

### `my.containers.qbittorrent`

- **Declared:** `nix-presets/containers/qbittorrent.nix:16`
- **Sub-options:** `downloadsDir`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `torrentingPort`, `webuiPort`
- **Configured in:** `host:nasbook`

### `my.containers.qdrant`

- **Declared:** `nix-presets/containers/qdrant.nix:14`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `package`
- **Configured in:** `host:nasbook`, `host:nixos-nvme`

### `my.containers.revue`

- **Declared:** `nix-presets/containers/revue.nix:28`
- **Sub-options:** `databaseUrl`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `meshLlmUrl`, `port`, `secretsFile`
- **Configured in:** _(not set anywhere)_

### `my.containers.stalwart`

- **Declared:** `nix-presets/containers/stalwart.nix:27`
- **Sub-options:** `adminPasswordFile`, `domain`, `enable`, `hostDataDir`, `ip`, `memoryLimit`, `relaySecretFile`
- **Configured in:** `host:mac-mini`

### `my.containers.syncthing`

- **Declared:** `nix-presets/containers/syncthing.nix:12`
- **Sub-options:** `enable`, `hostDataDir`, `ip`, `memoryLimit`, `secretsFile`, `user`, `vaults`
- **Configured in:** `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.containers.vaultwarden`

- **Declared:** `nix-presets/containers/vaultwarden.nix:23`
- **Sub-options:** `adminTokenFile`, `domain`, `enable`, `hostDataDir`, `invitationsAllowed`, `ip`, `memoryLimit`, `port`, `signupsAllowed`, `smtp`
- **Configured in:** `host:core-pi`

## `my.dataDisk`

### `my.dataDisk`

- **Declared:** `nix-config/modules/nixos/data-disk.nix:13`
- **Sub-options:** `cryptName`, `crypttabExtraOpts`, `device`, `enable`, `label`, `mountpoint`, `stage2KeyFile`
- **Configured in:** `host:nasbook`, `host:nixos-nvme`

## `my.deploy`

### `my.deploy.autoUpgrade`

- **Declared:** `nix-config/modules/nixos/auto-upgrade.nix:44`
- **Sub-options:** `allowReboot`, `cacheUrl`, `dates`, `enable`, `flakeRef`, `hostName`, `maxRuntime`, `ntfy.debounceSec`, `ntfy.enable`, `ntfy.tokenFile`, `ntfy.topicFile`, `ntfy.url`, `randomizedDelaySec`, `requireCache`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.deploy.comin`

- **Declared:** `nix-config/modules/nixos/comin.nix:33`
- **Sub-options:** `branch`, `buildTimeout`, `enable`, `exporter.enable`, `exporter.port`, `hostName`, `pollPeriod`, `requireCache`, `testingBranch`, `url`, `verifySignatures`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:orin-nano`

## `my.desktop`

### `my.desktop`

- **Declared:** `nix-config/modules/nixos/desktop.nix:28`
- **Sub-options:** `gnome.enable`
- **Configured in:** `host:mac-mini`, `host:nixos-nvme`

### `my.desktop.bottles`

- **Declared:** `nix-presets/nixosModules/bottles.nix:13`
- **Sub-options:** `enable`
- **Configured in:** `host:nixos-nvme`

### `my.desktop.claude`

- **Declared:** `nix-presets/nixosModules/claude.nix:39`
- **Sub-options:** `enable`
- **Configured in:** `host:nixos-nvme`

### `my.desktop.sandboxedApps`

- **Declared:** `nix-presets/nixosModules/sandboxed-apps.nix:20`
- **Sub-options:** `apps`, `enable`
- **Configured in:** `host:mac-mini`, `host:nixos-nvme`

## `my.hardware`

### `my.hardware.rpi-direct-boot`

- **Declared:** `nix-config/modules/nixos/rpi-direct-boot.nix:12`
- **Sub-options:** `enable`
- **Configured in:** _(not set anywhere)_

## `my.heartbeat`

### `my.heartbeat`

- **Declared:** `nix-config/modules/nixos/heartbeat.nix:53`
- **Sub-options:** `baseUrl`, `checks`, `enable`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:orin-nano`

## `my.herdr-remote-client`

### `my.herdr-remote-client`

- **Declared:** `nix-presets/herdr-remote-client.nix:12`
- **Sub-options:** `enable`, `serverAlias`, `serverIp`, `serverUser`, `shellAlias`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:orin-nano`

## `my.hostSecrets`

### `my.hostSecrets`

- **Declared:** `nix-config/modules/nixos/host-secrets.nix:11`
- **Sub-options:** `dir`, `initrdSshKey`
- **Configured in:** _(not set anywhere)_

## `my.monitoring`

### `my.monitoring.node`

- **Declared:** `nix-presets/nixosModules/monitoring-node.nix:43`
- **Sub-options:** `enable`
- **Configured in:** `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

## `my.security`

### `my.security.ai-hardening`

- **Declared:** `nix-config/modules/nixos/ai-hardening.nix:20`
- **Sub-options:** `airlockIPs`, `enable`, `strictEgress`, `whitelistDomains`
- **Configured in:** `host:nixos-nvme`, `host:orin-nano`

## `my.services`

### `my.services.cloudflareTunnel`

- **Declared:** `nix-config/modules/nixos/services/cloudflare-tunnel.nix:18`
- **Sub-options:** `enable`
- **Configured in:** `host:core-pi`

### `my.services.meshLlm`

- **Declared:** `nix-config/modules/nixos/services/mesh-llm.nix:24`
- **Sub-options:** `autoStart`, `enable`, `extraArgs`, `joinTokenSecret`, `meshPort`, `models`, `package`
- **Configured in:** `host:nixos-nvme`, `host:orin-nano`

### `my.services.photo-frame`

- **Declared:** `nix-presets/nixosModules/photo-frame/default.nix:19`
- **Sub-options:** `enable`, `openFirewallOn`, `photoDir`, `port`, `supplementaryGroups`
- **Configured in:** `host:hass-pi`

### `my.services.printing`

- **Declared:** `nix-config/modules/nixos/printing.nix:14`
- **Sub-options:** `enable`
- **Configured in:** `host:nixos-nvme`

### `my.services.rpi-eeprom`

- **Declared:** `nix-config/modules/nixos/services/rpi-eeprom.nix:13`
- **Sub-options:** `autoApply`, `enable`, `schedule`
- **Configured in:** _(not set anywhere)_

### `my.services.snapper`

- **Declared:** `nix-config/modules/nixos/snapper.nix:12`
- **Sub-options:** `enable`
- **Configured in:** `host:nixos-nvme`

### `my.services.tang`

- **Declared:** `nix-config/modules/nixos/services/tang.nix:11`
- **Sub-options:** `enable`
- **Configured in:** `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

### `my.services.threeDPrinting`

- **Declared:** `nix-config/modules/nixos/threed-printing.nix:16`
- **Sub-options:** `enable`
- **Configured in:** `host:nixos-nvme`

### `my.services.timesync`

- **Declared:** `nix-config/modules/nixos/services/timesync.nix:34`
- **Sub-options:** `enable`, `persistentClock.enable`, `persistentClock.path`
- **Default-enabled.** Active on: `host:core-pi`, `host:hass-pi`, `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`, `host:orin-nano`

## `my.virtualisation`

### `my.virtualisation`

- **Declared:** `nix-config/modules/nixos/virtualisation.nix:27`
- **Sub-options:** `enable`, `libvirtd.enable`, `podman.enable`
- **Configured in:** `host:mac-mini`, `host:nasbook`, `host:nixos-nvme`

