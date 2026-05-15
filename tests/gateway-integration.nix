_:

{
  name = "gateway-integration-test";

  nodes = {
    # Node 1: The Caddy Gateway
    gateway =
      { pkgs, ... }:
      {
        services.caddy = {
          enable = true;
          virtualHosts."test.local".extraConfig = ''
            reverse_proxy localhost:8080
          '';
        };

        # Mock backend service
        systemd.services.mock-backend = {
          wantedBy = [ "multi-user.target" ];
          script = ''
            ${pkgs.python3}/bin/python3 -m http.server 8080
          '';
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];
      };

    # Node 2: The Client
    client = _: {
      # Basic client configuration
    };
  };

  # The Python Test Script (The "Brain")
  testScript = ''
    start_all()

    # Wait for the gateway to be ready
    gateway.wait_for_unit("caddy.service")
    gateway.wait_for_unit("mock-backend.service")
    gateway.wait_for_open_port(80)

    # Verify that the gateway can reach its own backend
    gateway.succeed("curl -f -H 'Host: test.local' http://localhost")

    # Verify that the client can reach the gateway over the virtual network
    client.wait_for_unit("network.target")
    client.succeed("curl -f -H 'Host: test.local' http://gateway")
  '';
}
