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
    inputs.nix-presets.nixosModules.vllm
  ];

  networking.hostName = "rpi5-1";

  # ─── Virtualization ─────────────────────────────────────────
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  my = {
    # ─── Frontend Services ──────────────────────────────────────
    containers = {
      open-webui = {
        enable = true;
        ip = "10.85.46.102/24";
        hostDataDir = "/var/lib/open-webui";
        vllmUrl = "https://litellm.internal";
        memoryLimit = "2G";
      };

      # Smart Home Management
      home-assistant = {
        enable = true;
        ip = "10.85.46.10/24";
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
        ip = "10.85.46.113/24";
        hostDataDir = "/var/lib/agent-zero";
        vllmUrl = "https://litellm.internal";
      };

      # ─── vLLM (CPU-only optimized for RPi 5) ────────────────────
      vllm = {
        enable = true;
        ip = "10.85.46.117/24";
        hostDataDir = "/var/lib/vllm";
        image = "vllm/vllm-openai-cpu:latest-arm64";
        device = "cpu";
        maxModelLen = 4096;
        memoryLimit = "6G";
        enforceEager = true;
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
