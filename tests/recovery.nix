{ pkgs, inputs, ... }:

pkgs.testers.nixosTest {
  name = "recovery-integration-test";

  nodes = {
    backup_server =
      {
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          inputs.nix-presets.nixosModules.backup
        ];

        options.my.network.bridge = lib.mkOption {
          type = lib.types.str;
          default = "br0";
        };

        config = {
          my.network.bridge = "br0";

          # Create the bridge interface for the container
          networking.bridges.br0.interfaces = [ ];
          networking.interfaces.br0.ipv4.addresses = [
            {
              address = "10.85.46.1";
              prefixLength = 24;
            }
          ];

          # Mock secrets
          systemd.services.mock-secrets = {
            description = "Create mock secrets for backup test";
            wantedBy = [ "multi-user.target" ];
            before = [ "container@backup.service" ];
            serviceConfig.Type = "oneshot";
            script = ''
              mkdir -p /run/secrets
              echo "testpassword" > /run/secrets/restic_password
              mkdir -p /tmp/restic-repo
              chmod 777 /tmp/restic-repo
            '';
          };

          my.containers.backup = {
            enable = true;
            passwordFile = "/run/secrets/restic_password";
            systemPasswordFile = "/run/secrets/restic_password";
            # Use LOCAL backend for the test to avoid rclone mocking issues
            targets = {
              "/data" = "/srv/important-data";
            };
          };

          # Inject the mock storage and target into the container
          containers.backup.bindMounts = {
            "/mnt/restic-repo" = {
              hostPath = "/tmp/restic-repo";
              isReadOnly = false;
            };
            "/data" = {
              hostPath = "/srv/important-data";
              isReadOnly = lib.mkForce false; # Allow restoration in the test!
            };
          };

          # Override the restic service inside the container to use local path
          containers.backup.config = {
            environment.systemPackages = [ pkgs.restic ];
            services.restic.backups.daily = {
              initialize = true;
              repository = lib.mkForce "/mnt/restic-repo";
              # Clear rclone options if they were inherited
              extraOptions = lib.mkForce [ ];
            };
            services.restic.backups.system.timerConfig.OnCalendar = lib.mkForce "";
          };

          # Create some initial data
          systemd.services.init-data = {
            description = "Initialize data for backup";
            wantedBy = [ "multi-user.target" ];
            script = ''
              mkdir -p /srv/important-data
              echo "SECRET_MESSAGE_12345" > /srv/important-data/secret.txt
            '';
          };
        };
      };
  };

  testScript = ''
    backup_server.wait_for_unit("multi-user.target")
    backup_server.wait_for_unit("container@backup.service")

    with subtest("Verify initial data exists"):
        backup_server.succeed("grep SECRET_MESSAGE_12345 /srv/important-data/secret.txt")

    with subtest("Trigger manual backup"):
        # Start the service and WAIT for it to finish
        (status, output) = backup_server.execute("nixos-container run backup -- systemctl start --wait restic-backups-daily.service 2>&1")
        
        # Log journal on failure
        if status != 0:
            backup_server.log("Backup service journal:")
            backup_server.execute("nixos-container run backup -- journalctl -u restic-backups-daily.service --no-pager >&2")
            raise Exception("Backup service failed")

    with subtest("Verify repository files"):
        backup_server.succeed("nixos-container run backup -- ls -R /mnt/restic-repo")

    with subtest("Simulate data loss"):
        backup_server.succeed("rm -rf /srv/important-data/*")
        backup_server.fail("ls /srv/important-data/secret.txt")

    with subtest("Perform recovery"):
        # Run restic restore inside the container
        backup_server.succeed(
            "nixos-container run backup -- restic -r /mnt/restic-repo "
            "--password-file /run/secrets/restic_password "
            "restore latest --target /"
        )

    with subtest("Verify data is restored"):
        backup_server.succeed("grep SECRET_MESSAGE_12345 /srv/important-data/secret.txt")
  '';
}
