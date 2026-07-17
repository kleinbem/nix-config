# nasbook — QNAP TBS-453A
{
  inputs,
  self,
  myInventory,
  config,
  ...
}:
{
  imports = [
    # IMPORTANT: You must run `nixos-generate-config` on the physical NASbook
    # and replace/create `./hardware-configuration.nix` with the output.
    ./hardware-configuration.nix
    "${self}/modules/nixos/base.nix" # foundational, imported by every entry-point bundle
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"

    # ─── Services moved from Workstation ─────────────────────
    inputs.nix-presets.nixosModules.paperless
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.backup

    # Needs SOPS to unlock the secrets below
    ./secrets.nix
  ];

  networking.hostName = "nasbook";

  my = {
    # Pull-deploy; substitute-only — this laptop is too weak for long builds.
    # Gate the nightly run on cache reachability and cap its runtime.
    deploy.autoUpgrade = {
      enable = true;
      requireCache = true;
    };

    network = {
      subnet = "10.85.47.0/24";
      hostAddress = "10.85.47.1";
      externalInterface = "enp2s0";
    };

    # ─── Data & Analytics Hub Services ───────────────────────
    containers = {
      paperless = {
        enable = true;
        ip = "${myInventory.network.nodes.paperless.ip}/24";
        hostDataDir = "/mnt/data/Archive/Paperless";
        hostConsumptionDir = "/mnt/data/Archive/Inbox";
        passwordFile = config.sops.secrets.paperless_password.path;
      };

      agent-team = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-team.ip}/24";
      };

      monitoring = {
        enable = false;
        ip = "${myInventory.network.nodes.monitoring.ip}/24";
        hostDataDir = "/var/lib/images/monitoring";
        # Automatically scrape the host and important infrastructure nodes
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.core-gateway.ip
          myInventory.hosts.ap-upstairs.ip
        ];
      };

      loki = {
        enable = true;
        ip = "${myInventory.network.nodes.loki.ip}/24";
        hostDataDir = "/var/lib/images/loki";
      };

      qdrant = {
        enable = true;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
      };

      syncthing = {
        enable = true;
        ip = "10.85.47.127/24";
        hostDataDir = "/var/lib/images/syncthing";
        # Syncing from Google Drive / Local Data
        vaults = {
          "/mnt/data/GoogleDrive" = "/mnt/data/GoogleDrive";
        };
      };

      backup = {
        enable = true;
        ip = "${myInventory.network.nodes.backup.ip}/24";
        passwordFile = config.sops.secrets.restic_password.path;
        systemPasswordFile = config.sops.secrets.restic_system_password.path;
        rcloneConfigFile = config.sops.secrets.rclone_config.path;
        targets = {
          "/mnt/data" = "/mnt/data";
        };
        systemTargets = {
          "/var/lib/images" = "/var/lib/images";
        };
      };
    };
    monitoring.node.enable = true;
  };

  # IMAGE STATE STORAGE
  systemd.tmpfiles.rules = [
    "d /var/lib/images 0755 root root - -"
    "d /var/lib/images/loki 0755 root root - -"
    "d /var/lib/images/monitoring 0755 root root - -"
    "d /var/lib/images/qdrant 0755 root root - -"
    "d /var/lib/images/syncthing 0755 root root - -"
    "d /mnt/data/Archive 0755 martin users - -"
    "d /mnt/data/Archive/Inbox 0755 martin users - -"
    "d /mnt/data/Archive/Paperless 0755 root root - -"
  ];

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;
    fstrim.enable = true;
  };

  networking.firewall = {
    enable = true;
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  system.stateVersion = "25.11"; # Or whatever the current state version is
  my.services.tang.enable = true;
}
