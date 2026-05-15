{ pkgs, inputs, ... }:

let
  myInventory = import ../inventory.nix;
in
pkgs.testers.runNixOSTest {
  name = "caddy-native-infrastructure-test";

  nodes = {
    # The Caddy Reverse Proxy (Defined as a list of clean modules)
    gateway = {
      _module.args = { inherit myInventory; };

      imports = [
        inputs.nix-presets.nixosModules.caddy
        # A submodule to define our missing options
        (
          { lib, ... }:
          {
            options.my.network.bridge = lib.mkOption {
              type = lib.types.str;
              default = "cbr0";
            };
          }
        )
      ];

      # Backend service directly on the host for simplicity in testing
      services.httpd = {
        enable = true;
        virtualHosts."webserver" = {
          documentRoot = pkgs.writeTextDir "index.html" "<h1>Hello from Native Backend</h1>";
          listen = [
            {
              ip = "*";
              port = 8080;
            }
          ];
        };
      };

      networking = {
        nat = {
          enable = true;
          externalInterface = "eth1";
          forwardPorts = [
            {
              proto = "tcp";
              sourcePort = 80;
              destination = "10.85.46.10:80";
            }
          ];
        };

        firewall.allowedTCPPorts = [
          80
          8080
        ];
      };

      virtualisation.oci-containers.backend = "podman";

      my.containers.caddy.enable = pkgs.lib.mkForce false; # Disable preset to avoid conflicts

      containers.caddy = {
        autoStart = true;
        privateNetwork = true;
        hostAddress = "10.85.46.1";
        localAddress = "10.85.46.10";

        config = {
          services.caddy.enable = true;
          services.caddy.virtualHosts."http://app.local" = {
            extraConfig = ''
              reverse_proxy 10.85.46.1:8080
            '';
          };
          networking.firewall.enable = false;
          networking.defaultGateway = "10.85.46.1";
          system.stateVersion = "25.11";
        };
      };

      system.stateVersion = "25.11";
    };

    # The client node
    client = _: {
      system.stateVersion = "25.11";
    };
  };

  testScript = ''
    start_all()

    # Wait for the stack to initialize
    try:
        gateway.wait_for_unit("container@caddy.service")
    except Exception as e:
        gateway.log("Container 'caddy' failed to start! Fetching logs...")
        gateway.execute("systemctl status container@caddy >&2")
        gateway.execute("journalctl -u container@caddy --no-pager >&2")
        raise e
    gateway.wait_for_unit("httpd.service")
    client.wait_for_unit("network.target")

    # --- DEBUG SECTION ---
    # 1. Can the Client even see the Gateway?
    client.succeed("ping -c 1 gateway")

    # 2. Can the Gateway reach its own Caddy container?
    gateway.log("Checking internal container connectivity...")
    gateway.succeed("ping -c 1 10.85.46.10") 

    # 3. Does Caddy respond internally?
    gateway.succeed("curl -f http://10.85.46.10")
    # --- END DEBUG ---

    # 1. Verify that the Client can access the app THROUGH Caddy's NAT and Container
    client.log("Testing access to app.local via Caddy...")
    response = client.succeed("curl -v -f -H 'Host: app.local' http://gateway")

    assert "Hello from Native Backend" in response
    client.log("✅ Success: Native NixOS testing is working without hacks!")
  '';
}
