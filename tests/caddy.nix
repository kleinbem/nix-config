{ pkgs, inputs, ... }:

let
  myInventory = import ../inventory.nix;
in
pkgs.testers.runNixOSTest {
  name = "caddy-multi-node-infrastructure-test";

  nodes = {
    # The Caddy Reverse Proxy
    gateway =
      { config, nodes, ... }:
      {
        imports = [ inputs.nix-presets.nixosModules.caddy ];

        # Mock dependencies
        options.my.network.bridge = pkgs.lib.mkOption {
          type = pkgs.lib.types.str;
          default = "cbr0";
        };

        config = {
          _module.args = {
            myInventory = myInventory // {
              network = myInventory.network // {
                nodes = myInventory.network.nodes // {
                  caddy = {
                    ip = "10.85.46.10";
                  };
                  app = {
                    ip = nodes.webserver.networking.primaryIPAddress;
                    port = 8080;
                    externalPort = 80;
                  };
                };
              };
            };
          };

          networking = {
            nat = {
              enable = true;
              internalInterfaces = [ config.my.network.bridge ];
              externalInterface = "eth1";
            };
            bridges."${config.my.network.bridge}".interfaces = [ ];
            interfaces."${config.my.network.bridge}".ipv4.addresses = [
              {
                address = "10.85.46.1";
                prefixLength = 24;
              }
            ];
            firewall.allowedTCPPorts = [ 80 ];
          };

          virtualisation.oci-containers.backend = "podman";
          my.containers.caddy = {
            enable = true;
            ip = "10.85.46.10";
            hostDataDir = "/tmp/caddy-data";
          };

          # Fix the container isolation and add port forwarding
          containers.caddy = {
            forwardPorts = [
              {
                containerPort = 80;
                hostPort = 80;
                protocol = "tcp";
              }
            ];
            config = {
              # Disable the Zero Trust firewall for the test to allow reaching 'webserver'
              networking.nftables.tables.zt-factory.content = pkgs.lib.mkForce "";
            };
          };

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

    client =
      { nodes, ... }:
      {
        config = {
          _module.args = { inherit myInventory; };
          networking.extraHosts = "${nodes.gateway.networking.primaryIPAddress} app.local";
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

    # Debug: Check gateway state
    gateway.log(gateway.succeed("ip addr"))

    # 1. Verify internal connectivity
    gateway.wait_until_succeeds("ping -c 1 webserver")
    client.wait_until_succeeds("ping -c 1 gateway")

    # 2. Verify Client can access the app THROUGH Caddy
    client.log("Attempting to access app.local via Caddy gateway...")
    # Increase timeout for the first run
    response = client.succeed("curl -v -L --connect-timeout 10 http://app.local")

    assert "Hello from Internal App" in response
    client.log("✅ Success: Multi-node proxying is working!")
  '';
}
