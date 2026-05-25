# core-pi — Raspberry Pi 5
{
  inputs,
  self,
  myInventory,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/virtualisation.nix"
    "${self}/modules/nixos/zero-trust.nix"
    "${self}/modules/nixos/pki.nix"
    "${self}/modules/nixos/networking.nix"
    "${self}/modules/nixos/network-routing.nix"
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.cups
  ];

  networking.hostName = "core-pi";

  my = {
    services.rpi-eeprom.enable = true;

    network = {
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
      externalInterface = "end0";
    };

    # ─── Frontend Services ──────────────────────────────────────
    containers = {
      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        vllmUrl = "https://litellm.internal";
        memoryLimit = "1.5G";
      };

      # ─── AI Agents (Ready for deployment) ───────────────────────
      # These are hosted on the Pi to keep the Orin Nano slim.
      openclaw = {
        enable = false; # Set to true to enable
        vllmUrl = "https://litellm.internal";
        hostDataDir = "/var/lib/openclaw";
      };

      agent-zero = {
        enable = false; # Set to true to enable
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
        vllmUrl = "https://litellm.internal";
      };

      # ─── Ollama (Offloaded to Orin Nano) ────────────────────────
      ollama.enable = false;

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
        hostBridgeIp = "192.168.1.20"; # core-pi IP
        memoryLimit = "512M";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };
    };
    monitoring.node.enable = true;
  };

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;

    # SSD Health
    fstrim.enable = true;
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "10.85.46.104"; # Orin Nano via NetBird Mesh
        sshUser = "martin";
        systems = [ "aarch64-linux" ];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };

  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  system.stateVersion = "25.11";
}
