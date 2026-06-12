{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  # nix-mineral hardening module
  imports = [ inputs.nix-mineral.nixosModules.nix-mineral ];

  # ==========================================
  # NIX-MINERAL — Standard Hardening
  # ==========================================
  nix-mineral = {
    # x86_64 only: nix-mineral's kernel boot params (iommu=force, cfi=kcfi,
    # vsyscall=none, panic=-1, …) are x86-desktop-oriented and panic the
    # aarch64 Jetson/RPi kernel at boot (panic=-1 then instant-reboots, hiding
    # it → boot loop). Gate to x86 so ARM SBCs boot. (filesystem hardening also
    # disabled below to prevent nosuid root lockout.)
    enable = pkgs.stdenv.hostPlatform.isx86_64;
    preset = "compatibility"; # Best for desktop/workstation workloads

    # Disable filesystem hardening to prevent 'nosuid' root lockout and
    # prevent breaking /var/lib/machines where our systemd-nspawn containers run
    filesystems.enable = false;

    settings = {
      # Custom overrides for workstation needs
      network.ip-forwarding = true; # Required for containers/bridges
      system.multilib = true; # Required for some development tools
    };
  };

  environment.systemPackages = with pkgs; [
    apparmor-profiles # Pre-built profiles for ClamAV, Dnsmasq, etc.
  ];

  security = {
    apparmor = {
      enable = true;
      killUnconfinedConfinables = false;
    };
    protectKernelImage = true;

    # Increase password hashing rounds (Lynis Suggestion AUTH-9230)
    loginDefs.settings = {
      SHA_CRYPT_MIN_ROUNDS = 100000;
      SHA_CRYPT_MAX_ROUNDS = 100000;
    };
  };

  systemd = {
    # Prevent audit rule loading failures from blocking activation
    # (the kernel audit subsystem may be locked/busy during live switch;
    #  rules load correctly on next boot)
    services.audit-rules-nixos.serviceConfig.SuccessExitStatus = [ 1 ];

    # Relax seccomp hardening for jitterentropy to allow mlock (syscall 149)
    services.jitterentropy.serviceConfig.SystemCallFilter = lib.mkForce [
      "@system-service"
      "~@chown @clock @cpu-emulation @debug @ipc @module @mount @obsolete @privileged @raw-io @reboot @swap memfd_create mincore personality"
    ];
  };

  boot = {
    # Security & Performance Tweaks
    blacklistedKernelModules = [
      "pcspkr"
      "snd_pcsp"
    ];

    kernel.sysctl = {
      # ==========================================
      # AI-HARDENING COMPATIBILITY
      # ==========================================
      # Ensure unprivileged user namespaces are ENABLED (Nspawn needs them)
      # nix-mineral or other hardening might disable them by default.
      "kernel.unprivileged_userns_clone" = lib.mkForce 1;
      "kernel.perf_event_paranoid" = lib.mkForce 2;
    };
  };
}
