# Global Topology Definition
# Renders infrastructure diagrams from NixOS configurations.
# Build: nix build .#topology.x86_64-linux.config.output

let
  inv = import ./inventory.nix;
in
{
  # ─── Networks ──────────────────────────────────────────────
  networks.container-bridge = {
    name = "Container Bridge (${inv.network.bridge})";
    cidrv4 = inv.network.subnet;
  };

  networks.home = {
    name = "Home LAN";
    cidrv4 = "10.0.0.0/16";
  };

  # ─── External Devices ─────────────────────────────────────
  nodes = {
    internet = {
      deviceType = "internet";
      interfaces.wan = { };
    };

    router = {
      deviceType = "router";
      name = "Home Router";
      interfaces.wan.physicalConnections = [
        {
          node = "internet";
          interface = "wan";
        }
      ];
      interfaces.lan = {
        network = "home";
      };
    };

    # ─── Host: nixos-nvme ──────────────────────────────────────
    # The main workstation.
    nixos-nvme = {
      interfaces.wlo1 = {
        network = "home";
        physicalConnections = [
          {
            node = "router";
            interface = "lan";
          }
        ];
      };
      interfaces.${inv.network.bridge} = {
        network = "container-bridge";
      };
    };
  };
}
