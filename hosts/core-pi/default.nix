# core-pi — Raspberry Pi 5 (AI & Infrastructure Services)
{
  config,
  inputs,
  self,
  myInventory,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.monitoring
  ];

  networking.hostName = "core-pi";

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "core_crypt";
      hostIp = "10.0.0.22";
      secretFile = "${./cryptroot.jwe}";
    };

    # ─── Container Network ──────────────────────────────────────
    network = {
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
    };

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        memoryLimit = "2G";
      };

      openclaw = {
        enable = true;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/openclaw";
        memoryLimit = "1G";
      };

      agent-zero = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
        memoryLimit = "1G";
      };

      anythingllm = {
        enable = true;
        ip = "${myInventory.network.nodes.anythingllm.ip}/24";
        hostDataDir = "/var/lib/anythingllm";
        llmUrl = "https://litellm.internal";
        modelName = "google/gemma-2b"; # Aligned with Orin Nano backend in ai.nix
        memoryLimit = "2G";
      };

      dashboard = {
        enable = true;
        ip = "10.85.48.103/24";
        hostBridgeIp = "10.0.0.22"; # core-pi IP
        memoryLimit = "512M";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      github-runner = {
        enable = false; # Disabled until core-pi is physically online
        ip = "${myInventory.network.nodes.github-runner.ip}/24"; # Need to ensure this doesn't conflict if nvme also runs one
        hostDataDir = "/var/lib/github-runner";
        # secretsFile = config.sops.secrets.github_runner_pat.path;
      };

      authelia = {
        enable = true;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };

      attic = {
        enable = true;
        ip = "${myInventory.network.nodes.attic.ip}/24";
        hostDataDir = "/var/lib/images/attic";
        secretsFile = config.sops.templates."attic.env".path;
      };

      monitoring = {
        enable = true;
        ip = "10.85.48.114/24";
        hostDataDir = "/var/lib/monitoring";
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.router-1.ip
          myInventory.hosts.router-2.ip
          myInventory.hosts.core-pi.ip
          myInventory.hosts.hass-pi.ip
        ];
        githubMetrics.enable = false;
      };
    };
  };

  # ─── Persistence ─────────────────────────────────────────────
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/open-webui"
      "/var/lib/openclaw"
      "/var/lib/agent-zero"
      "/var/lib/anythingllm"
      "/var/lib/monitoring"
    ];
  };
}
