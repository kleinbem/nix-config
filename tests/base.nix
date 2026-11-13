# Common mock options and base configuration for headless NixOS integration tests.
{ lib, ... }:

{
  options.my = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "testuser";
      description = "Mock username for testing.";
    };

    network = {
      bridge = lib.mkOption {
        type = lib.types.str;
        default = "cbr0";
        description = "Mock bridge interface for container networking.";
      };
      hostAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.85.46.1";
        description = "Mock host gateway IP for container networking.";
      };
    };

    hardware.gpuRenderNode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Mock GPU render node.";
    };
  };

  config = {
    system.stateVersion = lib.mkDefault "25.11";
  };
}
