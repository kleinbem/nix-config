# orin-nano — NVIDIA Jetson Orin Nano (aarch64)
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    # Tier bundle + foundation
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"

    # Edge-device modules orin needs (curated — default.nix's workstation
    # bundle would also pull in snapper/printing/security/android which
    # don't apply to this host).
    "${self}/modules/nixos/kernel.nix" # BBR, memory tuning
    "${self}/modules/nixos/security/hardening.nix" # fleet hardening baseline (nix-mineral is x86-only)
    "${self}/modules/nixos/audit.nix" # security audit rules
    "${self}/modules/nixos/users.nix" # sops-backed root password, mutableUsers=false
    "${self}/modules/nixos/ai-hardening.nix" # AI workload sandboxing
    "${self}/modules/nixos/ananicy.nix" # process scheduler
    "${self}/modules/nixos/scripts.nix" # verify-system helpers
    "${self}/modules/nixos/clevis-initrd.nix" # Tang/clevis LUKS unlock
    "${self}/modules/nixos/initrd-fan.nix" # spin fan during initrd (pre-OS thermal safety)

    "${self}/users/martin/nixos.nix"
    inputs.nix-gantry.nixosModules.updater
    # Hardware support from our local hardware flake
    inputs.nix-hardware.nixosModules.orin-nano
    # Presets
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.llama-cpp
    inputs.nix-presets.nixosModules.frigate
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.attic-push
    inputs.nix-presets.nixosModules.herdr-remote-client
    # Disko configuration
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    "${self}/modules/nixos/persistence.nix"

    # Host-specific split modules
    ./hardware.nix
    ./network.nix
    ./services.nix
  ];

  networking.hostName = "orin-nano";

  my = {
    # External dead-man's switch (modules/nixos/heartbeat.nix): <host>-alive
    # every 5 min + a ping per backup job; missing pings alert from
    # healthchecks.io, outside the fleet. Always-on hosts only.
    heartbeat.enable = true;
    # comin pull-deploy (modules/nixos/comin.nix), rolled out fleet-wide
    # after the mac-mini canary (#201): follow the production branch, signed
    # heads only. Unlike the Pi tier this host still compiles its own
    # kernel/L4T closure on-device (build-all does not build orin-nano), so
    # requireCache stays off and comin's build timeout (default 30 min) is
    # raised to 12 h, the same "as long as it needs" rule autoUpgrade had.
    deploy = {
      autoUpgrade.enable = false;
      comin = {
        enable = true;
        requireCache = false;
        buildTimeout = 12 * 3600;
      };
    };

    attic-push = {
      enable = true;
      tokenFile = config.sops.secrets.attic_push_token.path;
    };

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Backups — nix-presets' backup-engine, fleet wiring in
    # modules/nixos/backup.nix. tang registers its own secure item.
    # Secrets: backup_r2_rclone_config (nix/per-host/orin-nano.yaml),
    # rclone_config/restic_password/ntfy_alert_topic (nix/shared.yaml).
    backup.enable = true;
  };

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowUnsupportedSystem = true;
    };
    overlays = [
      (
        final: prev:
        let
          jpPkgs = inputs.jetpack-nixos.legacyPackages.${prev.system};
          # Dynamically extract all Jetpack versions (nvidia-jetpack5, 6, 7, etc.)
          # so that when the default majorVersion bumps, it auto-switches safely.
          # We extract names from the overlay directly to avoid infinite recursion
          # caused by traversing the full Nixpkgs package set.
          jpOverlayAttrNames = builtins.attrNames (inputs.jetpack-nixos.overlays.default final prev);
          jetpackNames = lib.filter (lib.hasPrefix "nvidia-jetpack") jpOverlayAttrNames;
          jetpackOverrides = lib.genAttrs jetpackNames (name: jpPkgs.${name});
          # nixpkgs 09063bd ships System.map in kernel.dev (for
          # linuxPackages.rebuildImage), so kbuild's modules_install now runs
          # depmod for the out-of-tree L4T modules too. Their modules.dep then
          # collides with the kernel's in aggregateModules ("two given paths
          # contain a conflicting subpath", build-all run 39385551311). The
          # aggregator runs depmod over everything anyway, so skip it here,
          # like nixpkgs' amneziawg does. Self-retiring: skipped once
          # jetpack-nixos passes DEPMOD itself.
          withoutOotDepmod =
            jp:
            if !(jp ? kernelPackagesOverlay) then
              jp
            else
              jp
              // {
                kernelPackagesOverlay = lib.composeExtensions jp.kernelPackagesOverlay (
                  _: kprev:
                  lib.optionalAttrs (kprev ? nvidia-oot-modules) {
                    nvidia-oot-modules =
                      if lib.any (lib.hasPrefix "DEPMOD=") (kprev.nvidia-oot-modules.makeFlags or [ ]) then
                        kprev.nvidia-oot-modules
                      else
                        kprev.nvidia-oot-modules.overrideAttrs (old: {
                          makeFlags = (old.makeFlags or [ ]) ++ [ "DEPMOD=true" ];
                        });
                  }
                );
              };
          # nixpkgs 3fe146e660 (2026-10-21) dropped its pre-5.19 kernel
          # support, so buildLinux now always applies
          # randstruct-provide-seed-5.19.patch, which edits
          # scripts/gen-randstruct-seed.sh. The L4T 5.15 kernel doesn't have
          # that file (its seed script is scripts/gcc-plugins/gen-random-seed.sh),
          # so patchPhase fails for the kernel, its config and cpupower. Add
          # the file with its unpatched 5.19 content so the patch applies.
          # Nothing in 5.15 runs it, and the L4T config doesn't enable
          # GCC_PLUGIN_RANDSTRUCT. Self-retiring: skipped when the source
          # already has the file, and from 5.19 on.
          withRandstructSeedScript =
            jp:
            if !(jp ? overrideScope && jp ? kernel) then
              jp
            else
              jp.overrideScope (
                _: sprev: {
                  kernel = sprev.kernel.override (o: {
                    buildLinux =
                      args:
                      o.buildLinux (
                        args
                        // lib.optionalAttrs (lib.versionOlder args.version "5.19") {
                          src = final.applyPatches {
                            name = "linux-${args.version}-source";
                            inherit (args) src;
                            postPatch = ''
                              if [ ! -e scripts/gen-randstruct-seed.sh ]; then
                                cat > scripts/gen-randstruct-seed.sh <<'EOF'
                              #!/bin/sh
                              # SPDX-License-Identifier: GPL-2.0

                              SEED=$(od -A n -t x8 -N 32 /dev/urandom | tr -d ' \n')
                              echo "$SEED" > "$1"
                              HASH=$(echo -n "$SEED" | sha256sum | cut -d" " -f1)
                              echo "#define RANDSTRUCT_HASHED_SEED \"$HASH\"" > "$2"
                              EOF
                                chmod +x scripts/gen-randstruct-seed.sh
                              fi
                            '';
                          };
                        }
                      );
                  });
                }
              );
        in
        jetpackOverrides
        // {
          nvidia-jetpack = withoutOotDepmod (withRandstructSeedScript prev.nvidia-jetpack);
        }
        // lib.optionalAttrs (config.hardware.nvidia-jetpack.majorVersion == "6") {
          cudaPackages = final.cudaPackages_12_6;
        }
        // lib.optionalAttrs (config.hardware.nvidia-jetpack.majorVersion == "7") {
          # CUDA 13 on Tegra/aarch64 has no upstream cuda_compat package (driver 595 is base).
          # Stub cuda_compat in _cuda extensions to prevent unpackPhase failure on null $src in auto-add-cuda-compat-runpath-hook.
          _cuda = prev._cuda.extend (
            _: prevCuda: {
              extensions = prevCuda.extensions ++ [
                (_finalCuda: _prevCudaPkgs: {
                  cuda_compat = final.emptyDirectory;
                })
              ];
            }
          );
        }
      )
    ];
  };

  environment.systemPackages = with pkgs; [
    sops
    age
    libfido2

    inputs.jetpack-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.l4t-tools # Essential: provides tegrastats and L4T utilities
  ];

  nix.settings = {
    trusted-users = [
      "root"
      "martin"
    ];
    # Bounded build parallelism for 8GB Unified Memory:
    # 2 cores avoids thrashing LPDDR5 bandwidth and saturating swap when
    # compiling heavy Rust crates (e.g. mesh-llm), leaving room for Frigate + LLM.
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 2;
  };

  # Extra NVMe swapfile on /nix (ext4 on vg_orin-nix, 80 GB free) to give heavy
  # Rust builds (e.g. mesh-llm with thin LTO) enough headroom to finish without
  # running out of swap or tripping earlyoom.
  swapDevices = [
    {
      device = "/nix/persist/swapfile";
      size = 32 * 1024;
      priority = -10;
    }
  ];

  # Persist /var/cache so large caches (Trivy vuln database, fwupd) do not sit
  # on the 4G tmpfs root, permanently consuming RAM and swap.
  environment.persistence."/nix/persist".directories = [
    "/var/cache"
  ];

  services = {
    # Headless edge AI node: protect real-time camera streams, containers, and SSH
    # from OOM kills. Trigger only under genuine swap exhaustion (2% free) and low RAM (10% avail).
    # Do NOT prefer killing rustc/cargo/nix-daemon: long canary builds (mesh-llm) need to finish
    # without earlyoom terminating the compiler mid-flight.
    earlyoom.extraArgs = lib.mkForce [
      "-m"
      "10"
      "-s"
      "2"
      "--ignore"
      "^(frigate|mesh-llm|ollama|container@.*|sshd|systemd)$"
    ];
  };

  # colmena deploys as martin (PermitRootLogin = "no" in security.nix).
  # The blanket `ALL NOPASSWD` that used to live here is gone: the
  # fleet-wide per-command allowlist (modules/nixos/security/sudo.nix)
  # applies. Set `my.security.sudo.unattendedDeploy = true` if colmena
  # push deploys to this host must stay prompt-free.

  users.users = {
    martin.openssh.authorizedKeys.keys = [
      keys.ssh.yubikey
      keys.ssh.fido2
      keys.ssh.fido2-backup
    ];
    # No root keys (see hosts/mac-mini/default.nix for the reasoning); the
    # bootstrap installer image is the only root@ login left, and only
    # until `just deployment::orin-promote` replaces it.
  };

  # No desktop specialisation: orin-nano is a pure headless AI edge device.
  # Local debug is text-mode TTY on HDMI (agetty on tty1); remote work is SSH.
  # Need a remote Wayland app occasionally? `waypipe` it from your workstation.

  # Override headless.nix silent boot to keep console output visible.
  # HDMI (tty0) is BLACK during initrd on Jetson — the Tegra display driver
  # (nvidia-drm) only loads AFTER the LUKS unlock, so the passphrase prompt has
  # no framebuffer to render on. The Tegra debug UART (ttyTCU0, micro-USB debug
  # port) IS live from firmware, so list it LAST → it becomes the primary
  # /dev/console: the initrd/LUKS prompt is then visible AND enterable over
  # serial, while HDMI still shows everything once the system is up. Do NOT drop
  # ttyTCU0 again (an HDMI-only console makes a stale-JWE unlock failure an
  # invisible black-screen hang). See docs/ + the clevis-initrd setup.
  # This mkForce replaces the WHOLE kernelParams list, so anything NixOS or a
  # module would otherwise inject MUST be re-listed here or it is silently
  # dropped:
  #   - root=fstab       : systemd stage-1 mounts the tmpfs root via fstab;
  #                        without it → gpt-auto-root timeout → emergency mode.
  #   - systemd.machine_id: machine-id.nix's fleet-wide pin (my.machineId) —
  #                        without it systemd regenerates a random id every
  #                        boot ("Detected first boot" each time).
  # console=ttyTCU0 stays LAST so it is the primary /dev/console for the LUKS
  # prompt over the Tegra debug UART — do not reorder the console= entries.
  # Keep the id this host has always had (pre-dates machine-id.nix's
  # hostname-derived default).
  my.machineId = "9fef3c9be6eb4bf29456f7be28ec4d6d";
  boot.kernelParams = lib.mkForce [
    "root=fstab"
    "systemd.machine_id=${config.my.machineId}"
    "console=tty0"
    "console=ttyTCU0,115200"
  ];

  system.stateVersion = "25.11";
}
