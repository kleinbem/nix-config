{ pkgs, inputs, ... }:

let
  myInventory = import ../inventory.nix;
in
pkgs.testers.runNixOSTest {
  name = "caddy-multi-node-infrastructure-test";

  nodes = {
    # The Caddy Reverse Proxy
    gateway =
      { config, ... }:
      {
        imports = [ inputs.nix-presets.nixosModules.caddy ];

        # Mock dependencies
        options.my.network.bridge = pkgs.lib.mkOption {
          type = pkgs.lib.types.str;
          default = "cbr0";
        };

        config = {
          _module.args = { inherit myInventory; };

          networking = {
            bridges."${config.my.network.bridge}".interfaces = [ ];
            interfaces."${config.my.network.bridge}".ipv4.addresses = [
              {
                address = "10.88.0.1";
                prefixLength = 24;
              }
            ];
            firewall.allowedTCPPorts = [ 80 ];
          };

          virtualisation.oci-containers.backend = "podman";
          my.containers.caddy = {
            enable = true;
            ip = "10.88.0.10/24";
            hostDataDir = "/tmp/caddy-data";
          };

          # Configure a manual Caddyfile for the test to proxy to the 'webserver' node
          services.caddy.extraConfig = ''
            http://app.test {
              reverse_proxy http://webserver:8080
            }
          '';

          system.stateVersion = "25.11";
        };
      };

    webserver = _: {
      config = {
        _module.args = { inherit myInventory; };
        services.httpd = {
          enable = true;
          adminAddr = "test@example.org";
          virtualHosts."webserver" = {
            documentRoot = pkgs.writeTextDir "index.html" "<h1>Hello from Internal App</h1>";
            listen = [
              {
                ip = "*";
                port = 8080;
              }
            ];
          };
        };
        networking.firewall.allowedTCPPorts = [ 8080 ];
        system.stateVersion = "25.11";
      };
    };

    client = _: {
      config = {
        _module.args = { inherit myInventory; };
        networking.extraHosts = "10.88.0.10 app.test"; # Point to gateway
        system.stateVersion = "25.11";
      };
    };
  };

  testScript = ''
    # Start all nodes
    start_all()

    gateway.wait_for_unit("container@caddy.service")
    webserver.wait_for_unit("httpd.service")
    client.wait_for_unit("multi-user.target")

    # 1. Verify internal connectivity
    gateway.wait_until_succeeds("ping -c 1 webserver")
    client.wait_until_succeeds("ping -c 1 10.88.0.10") # Ping the gateway bridge/IP

    # 2. Verify Client can access the app THROUGH Caddy
    client.log("Attempting to access app.test via Caddy gateway...")
    response = client.succeed("curl -L http://app.test")

    assert "Hello from Internal App" in response
    client.log("✅ Success: Multi-node proxying is working!")
  '';
}
