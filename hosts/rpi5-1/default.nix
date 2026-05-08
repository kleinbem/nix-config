# rpi5-1 — Raspberry Pi 5
{ inputs, ... }:
let
  keys = import ../../modules/nixos/keys.nix;
in
{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.home-assistant
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.ollama
  ];

  networking.hostName = "rpi5-1";

  my = {
    # ─── Frontend Services ──────────────────────────────────────
    containers = {
      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        vllmUrl = "https://litellm.internal";
        memoryLimit = "2G";
      };

      # Smart Home Management
      home-assistant = {
        enable = true;
        ip = "${myInventory.network.nodes.home-assistant.ip}/24";
        hostDataDir = "/var/lib/home-assistant";
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

      # ─── Ollama (CPU-only for RPi 5) ────────────────────────────
      ollama = {
        enable = true;
        ip = "${myInventory.network.nodes.ollama-rpi.ip}/24";
        hostDataDir = "/var/lib/ollama";
        memoryLimit = "6G";
        # No acceleration = CPU-only (default)
      };
    };
    monitoring.node.enable = true;
  };

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;
    tailscale.enable = false;

    # SSD Health
    fstrim.enable = true;
  };

  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
  ];

  system.stateVersion = "25.11";
}
