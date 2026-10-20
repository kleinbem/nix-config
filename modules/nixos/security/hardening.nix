{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
# The fleet's one hardening layer. nix-mineral carries the bulk of it where
# it can run (x86_64); the manual baseline below covers what nix-mineral
# doesn't set, plus the same Lynis sysctls on hosts where nix-mineral is
# off (aarch64: its boot params panic the Jetson/RPi kernels).
#
# Compatibility overrides live here too, so a host never has to fight this
# module with mkForce: nspawn needs user namespaces, perf needs a relaxed
# paranoid level, containers need forwarding.
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

  boot = {
    # Lynis NETW-3200 plus the PC speaker. nix-mineral's own module
    # blacklist is off under the compatibility preset, so this list is
    # the fleet's.
    blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "pcspkr"
      "snd_pcsp"
    ];

    kernel.sysctl = lib.mkMerge [
      # Baseline nix-mineral would otherwise provide (same values). Only
      # declared where nix-mineral is off, so the two never disagree.
      (lib.mkIf (!mineral) {
        "kernel.sysrq" = 4; # sync, unmount, reboot only
        "kernel.kptr_restrict" = 2;
        "kernel.unprivileged_bpf_disabled" = 1;
        "kernel.dmesg_restrict" = 1;
        "kernel.randomize_va_space" = 2;
        "net.core.bpf_jit_harden" = 2;
        "vm.unprivileged_userfaultfd" = 0;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.log_martians" = 1;
        "net.ipv4.conf.default.log_martians" = 1;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
      })
      {
        # Compatibility overrides, everywhere.
        "kernel.unprivileged_userns_clone" = 1; # systemd-nspawn
        "kernel.perf_event_paranoid" = 2; # perf for unprivileged users (nix-mineral: 3)
      }
    ];
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
    tmpfiles.rules = [
      "d /var/account 0700 root root - -"
      "f /var/account/pacct 0600 root root - -"
    ];

    services = {
      acct = {
        description = "Process Accounting";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.acct}/bin/accton /var/account/pacct";
          ExecStop = "${pkgs.acct}/bin/accton off";
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
