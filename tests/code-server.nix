{ pkgs, inputs, ... }:

pkgs.testers.runNixOSTest {
  name = "code-server-integration-test";

  nodes.machine =
    { config, ... }:
    {
      imports = [
        inputs.nix-presets.nixosModules.code-server
      ];

      # Mock dependencies for a headless test
      options.my.username = pkgs.lib.mkOption {
        type = pkgs.lib.types.str;
        default = "testuser";
      };

      options.my.network = {
        bridge = pkgs.lib.mkOption {
          type = pkgs.lib.types.str;
          default = "cbr0";
        };
        hostAddress = pkgs.lib.mkOption {
          type = pkgs.lib.types.str;
          default = "10.88.0.1";
        };
      };

      config = {
        users.users.testuser = {
          isNormalUser = true;
          uid = 1000;
        };

        networking.bridges."${config.my.network.bridge}".interfaces = [ ];
        networking.interfaces."${config.my.network.bridge}".ipv4.addresses = [
          {
            address = "10.88.0.1";
            prefixLength = 24;
          }
        ];

        virtualisation.oci-containers.backend = "podman";

        my.containers.code-server = {
          enable = true;
          ip = "10.88.0.2/24";
          hostDataDir = "/tmp/code-server-data";
          user = "testuser";
          memoryLimit = "1G";
          privateUsers = "no";
        };

        system.stateVersion = "25.11";
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Wait for the container to initialize
    machine.log("Waiting for container@code-server.service to start...")
    machine.wait_for_unit("container@code-server.service")
    machine.log("Container unit is active. Checking connectivity...")

    # Connectivity check
    machine.wait_until_succeeds("ping -c 1 10.88.0.2", timeout=30)
    machine.log("Ping to 10.88.0.2 succeeded.")

    # Service port check
    machine.log("Waiting for port 4444 to open on 10.88.0.2...")
    try:
        machine.wait_for_open_port(4444, "10.88.0.2", timeout=60)
        machine.log("Port 4444 is open. Verifying application response...")
    except Exception as e:
        machine.log("Port 4444 did not open in time. Dumping container diagnostics...")
        # Check service status inside the container
        status = machine.succeed("systemctl -M code-server status code-server || true")
        machine.log(f"Container code-server status:\n{status}")
        # Check listening ports inside the container
        ports = machine.succeed("systemd-run -M code-server --wait --pipe ss -tulpn || true")
        machine.log(f"Container listening ports:\n{ports}")
        # Check logs
        logs = machine.succeed("journalctl -M code-server -u code-server --no-pager -n 50 || true")
        machine.log(f"Container service logs:\n{logs}")
        raise e

    # Assert that the code-server application is serving HTTP successfully
    response = machine.succeed("curl -v http://10.88.0.2:4444/")
    machine.log(f"Response received: {response[:100]}...")
    assert "code-server" in response.lower()
    machine.log("Verification successful!")
  '';
}
