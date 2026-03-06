{ pkgs, inputs, ... }:

pkgs.testers.runNixOSTest {
  name = "code-server-integration-test";

  nodes.machine = { ... }: {
    imports = [
      inputs.nix-presets.nixosModules.code-server
    ];

    # Mock dependencies for a headless test
    options.my.username = pkgs.lib.mkOption {
      type = pkgs.lib.types.str;
      default = "testuser";
    };

    config = {
      users.users.testuser = {
        isNormalUser = true;
        uid = 1000;
      };

      virtualisation.oci-containers.backend = "podman";

      my.containers.code-server = {
        enable = true;
        ip = "10.88.0.2/24";
        hostDataDir = "/tmp/code-server-data";
        user = "testuser";
        memoryLimit = "1G";
      };

      system.stateVersion = "25.11";
    };
  };

  testScript = ''
    machine.start()
    
    # Wait for the container to initialize and the service to be up
    machine.wait_for_unit("podman-code-server.service")
    machine.wait_for_open_port(8080)
    
    # Assert that the code-server application is serving HTTP successfully
    response = machine.succeed("curl -s http://localhost:8080/login")
    assert "code-server" in response.lower()
  '';
}
