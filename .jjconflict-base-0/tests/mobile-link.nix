{
  pkgs,
  inputs,
  self,
  ...
}:

let
  myInventory = import ../inventory.nix;
  # We reuse your actual phone package list to ensure the test is realistic
  phoneConfig = import ../hosts/phone/default.nix { inherit pkgs inputs self; };
in
pkgs.testers.runNixOSTest {
  name = "mobile-to-gateway-mesh-test";

  nodes = {
    # The Caddy Gateway (Target)
    gateway =
      { ... }:
      {
        _module.args = { inherit myInventory; };
        imports = [
          inputs.nix-presets.nixosModules.caddy
        ];

        services.caddy.enable = true;
        networking.firewall.allowedTCPPorts = [ 80 ];
        services.caddy.virtualHosts."http://vault.internal" = {
          extraConfig = ''
            respond "Access Granted to Mobile Client"
          '';
        };

        # Mock NetBird setup (using static IPs to simulate the mesh)
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.10.10.1";
            prefixLength = 24;
          }
        ];

        system.stateVersion = "25.11";
      };

    # The "Mock Phone" (Source)
    mock_phone =
      { ... }:
      {
        _module.args = { inherit myInventory; };
        # Use the same packages your real phone uses!
        environment.systemPackages = phoneConfig.environment.packages;

        # No custom modules needed for mock phone
        imports = [ ];

        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.10.10.2";
            prefixLength = 24;
          }
        ];

        # Simulate the 'Host' resolution that NetBird would provide
        networking.extraHosts = "10.10.10.1 vault.internal";

        system.stateVersion = "25.11";
      };
  };

  testScript = ''
    start_all()

    # Wait for services
    gateway.wait_for_unit("caddy.service")
    mock_phone.wait_for_unit("network.target")

    # 1. Verify basic mesh connectivity
    mock_phone.succeed("ping -c 1 10.10.10.1")

    # 2. Verify that the "Phone" can access the internal Vault via Caddy
    mock_phone.log("📱 Mobile Client attempting to access Internal Vault...")
    response = mock_phone.succeed("curl -f http://vault.internal")

    assert "Access Granted to Mobile Client" in response
    mock_phone.log("✅ Success: Mobile Mesh-to-Gateway link verified!")
  '';
}
