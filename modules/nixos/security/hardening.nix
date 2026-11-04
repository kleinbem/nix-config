{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
# The fleet's hardening layer: nix-mineral on x86_64 only (its boot params
# panic the Jetson/RPi kernels), plus what it doesn't set. Compatibility
# overrides live here too, so hosts never need mkForce against it.
let
  mineral = config.nix-mineral.enable;
  isX86 = pkgs.stdenv.hostPlatform.isx86_64;
in
{
  imports = [ inputs.nix-mineral.nixosModules.nix-mineral ];

  nix-mineral = {
    enable = isX86;
    preset = "compatibility";
    # nosuid on / and /var/lib would lock out root and break the nspawn
    # roots under /var/lib/machines.
    filesystems.enable = false;
    settings = {
      network.ip-forwarding = true; # containers / bridges
      system.multilib = true; # 32-bit tooling
    };
  };

  # The Lynis sysctls and the module blacklist are fleet-wide in
  # security/sysctl.nix (core.nix); nix-mineral's identical values win
  # there by priority. Only the compatibility overrides stay here.
  boot.kernel.sysctl = {
    "kernel.unprivileged_userns_clone" = 1; # systemd-nspawn
    "kernel.perf_event_paranoid" = 2; # perf for unprivileged users (nix-mineral: 3)
  };

  security = {
    # AppArmor is on only where it has been run: the x86 workstations.
    # Untested on the Jetson L4T and RPi kernels.
    apparmor = lib.mkIf isX86 {
      enable = true;
      killUnconfinedConfinables = false;
    };
    protectKernelImage = true;

    loginDefs.settings = {
      # Lynis AUTH-9286 password ageing, AUTH-9230 hashing rounds.
      PASS_MAX_DAYS = 180;
      PASS_MIN_DAYS = 1;
      PASS_WARN_AGE = 7;
      SHA_CRYPT_MIN_ROUNDS = 100000;
      SHA_CRYPT_MAX_ROUNDS = 100000;
    };
  };

  services = {
    # Lynis SSH-7408.
    openssh.settings.LogLevel = "VERBOSE";
    # Lynis BANN-7126.
    getty.greetingLine = lib.mkForce "Authorized Access Only. All activity is logged and monitored.";
  };

  # Lynis ACCT-9622: BSD process accounting. NixOS has no module for it.
  environment.systemPackages = [ pkgs.acct ];
  systemd = {
    tmpfiles.settings."10-process-accounting" = {
      "/var/account".d = {
        mode = "0700";
        user = "root";
        group = "root";
      };
      "/var/account/pacct".f = {
        mode = "0600";
        user = "root";
        group = "root";
      };
    };

    services = {
      acct = {
        description = "Process Accounting";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe' pkgs.acct "accton"} /var/account/pacct";
          ExecStop = "${lib.getExe' pkgs.acct "accton"} off";
        };
      };

      # The kernel audit subsystem can be busy during a live switch; rules
      # load on the next boot, so don't fail activation over it.
      audit-rules-nixos.serviceConfig.SuccessExitStatus = [ 1 ];

      # nix-mineral's jitterentropy-rngd needs mlock, which the stock filter
      # denies.
      jitterentropy.serviceConfig.SystemCallFilter = lib.mkIf mineral (
        lib.mkForce [
          "@system-service"
          "~@chown @clock @cpu-emulation @debug @ipc @module @mount @obsolete @privileged @raw-io @reboot @swap memfd_create mincore personality"
        ]
      );
    };
  };
}
