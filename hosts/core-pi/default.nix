# core-pi — Raspberry Pi 5 (AI & Infrastructure Services)
{
  inputs,
  self,
  myInventory,
  pkgs,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    ./disko.nix
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.cups
  ];

  networking.hostName = "core-pi";

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "core_crypt";
      hostIp = "10.0.0.22";
      secretFile = ./cryptroot.jwe;
      fallbackMessage = "Tang still unreachable; continuing (clevis falls back to passphrase)";
    };

    # ─── Container Network ──────────────────────────────────────
    network = {
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
    };

    virtualisation = {
      podman.enable = false;
      lxc.enable = false;
    };

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
      };

      openclaw = {
        enable = true;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/openclaw";
      };

      agent-zero = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
      };

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
        hostBridgeIp = "10.0.0.22"; # core-pi IP
        memoryLimit = "512M";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };
    };
  };

  # ─── Extra Packages ─────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    bind.dnsutils
  ];

  # ─── Persistence ─────────────────────────────────────────────
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/open-webui"
      "/var/lib/openclaw"
      "/var/lib/agent-zero"
      "/var/lib/anythingllm"
    ];
  };
}
