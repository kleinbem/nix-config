# mac-mini — Mid-2011 Mac Mini (Macmini5,x), Intel, real 64-bit EFI.
#
# Role: dedicated interactive box (no physical keyboard/mouse/screen — GUI
# access is remote-desktop only). First concrete use case: join/record Zoom
# calls from a container. Provisioned like orin-nano/core-pi/hass-pi — SSD
# wiped+installed via USB-SATA adapter (see .just/deployment.just
# mac-mini-install-usb), then moved internally.
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
    # Tier bundle + foundation (same trio orin-nano/nasbook import directly,
    # and core-pi/hass-pi get transitively via rpi5-node.nix).
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/clevis-initrd.nix"

    "${self}/users/martin/nixos.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    "${self}/modules/nixos/desktop.nix"

    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix

    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.herdr-remote-client
  ];

  # Same fleet-wide key set as every other host (modules/nixos/keys.nix).
  # headless.nix only creates the user; each host authorizes its own keys.
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  # Remote desktop: this host's whole reason for existing (see top-of-file
  # comment) is GUI access with zero physical keyboard/screen/console ever
  # attached. Was Wayland (sway) + wayvnc + noVNC (bespoke systemd services
  # driving a headless wlroots compositor by hand — see git history for that
  # setup); replaced with real GNOME (my.desktop.gnome.enable, the same
  # fleet-wide module nixos-nvme uses) via GDM autologin + GNOME Remote
  # Desktop's headless RDP daemon, which is the module's own supported
  # answer to "no physical display ever attached" rather than a hand-rolled
  # runtime dir + WLR_BACKENDS=headless trick.
  #
  # Auth/exposure: kept identical to the old wayvnc posture. RDP's only auth
  # is a username+password (grdctl-provisioned below), the same
  # weaker-than-FIDO2 tradeoff wayvnc had — so it stays OFF the firewall
  # entirely (no networking.firewall.allowedTCPPorts / openFirewall) and is
  # reachable only via `ssh -L 3389:localhost:3389 mac-mini` (FIDO2/Yubikey
  # pubkey, the fleet's real trust mechanism) + a local RDP client pointed
  # at localhost:3389. No NetBird ACL change needed — this never touches a
  # routable interface, same as wayvnc never did.
  #
  # UNVERIFIED so far (no physical monitor to watch a first boot on, and
  # this hasn't been through a real reboot test yet — see the mac-mini tg3
  # incident for why that matters): whether GDM autologin + gnome-shell
  # actually come up cleanly on this box's real Sandy Bridge iGPU with
  # nothing connected to its HDMI/DP port. Unlike tg3 (an initrd-level
  # failure with no network at all), a failed GNOME session here does NOT
  # take SSH/NetBird down with it — recover via `ssh mac-mini` +
  # `journalctl -u display-manager` / `systemctl --user status
  # gnome-remote-desktop-headless`, or roll back to the previous generation
  # over SSH, no physical access required.
  my.desktop.gnome.enable = true;

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = "martin";
    };
    defaultSession = "gnome";
  };

  services.gnome.gnome-remote-desktop.enable = true;

  # nixos-nvme disables GNOME's idle-suspend via a home-manager dconf setting
  # (modules/home-manager/gnome.nix, sleep-inactive-ac-type = "nothing"), but
  # that's only wired to martin's home-manager profile — mac-mini has no
  # home-manager at all (headless tier). Without this, GNOME's stock
  # idle-suspend default applies, and with zero physical peripherals ever
  # generating input, the box suspends itself shortly after autologin —
  # confirmed live 2026-08-03 (pulsing sleep LED, full ARP-level
  # unreachability including over NetBird) not long after a clean first
  # boot. programs.dconf.profiles.user is the non-home-manager equivalent:
  # a system-wide dconf default any user picks up, no home-manager needed.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing"; # no battery on this hardware, kept for consistency
      };
    }
  ];

  # grdctl writes RDP config into per-user dconf, which needs a real D-Bus
  # session + dconf — i.e. martin's actual logind session after autologin,
  # not a bespoke runtime dir the way wayvnc needed one. gnome-session.target
  # is exactly that context. Idempotent: password + TLS cert/key are
  # generated once and persisted (below), re-applied via grdctl on every
  # session start rather than regenerated.
  systemd.user.services.gnome-remote-desktop-rdp-setup = {
    description = "Provision GNOME Remote Desktop (headless RDP) credentials + TLS cert";
    wantedBy = [ "gnome-session.target" ];
    after = [ "gnome-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      state="$HOME/.local/share/gnome-remote-desktop-rdp"
      mkdir -p "$state"

      if [ ! -f "$state/password" ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 18 > "$state/password"
        chmod 600 "$state/password"
        echo "Generated a new GNOME Remote Desktop (RDP) password for martin — save it now: $(cat "$state/password")"
      fi

      if [ ! -f "$state/tls.crt" ] || [ ! -f "$state/tls.key" ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
          -subj "/CN=mac-mini" \
          -keyout "$state/tls.key" -out "$state/tls.crt" 2>/dev/null
        chmod 600 "$state/tls.key"
      fi

      grdctl="${pkgs.gnome-remote-desktop}/bin/grdctl"
      "$grdctl" --headless rdp set-tls-cert "$state/tls.crt"
      "$grdctl" --headless rdp set-tls-key "$state/tls.key"
      "$grdctl" --headless rdp set-credentials martin "$(cat "$state/password")"
      "$grdctl" --headless rdp enable
    '';
  };

  environment = {
    # /home has no disk-backed mount of its own (disko.nix only declares
    # /nix and /nix/persist) — it lives under the tmpfs "/" declared near
    # the bottom of this file, so it's wiped every reboot by default.
    # gnome-remote-desktop-rdp state (above) also needs to survive reboots —
    # without it the RDP password/cert would regenerate (and need
    # re-entering in a client) on every boot.
    persistence."/nix/persist".users.martin.directories = [
      ".mozilla" # Firefox profile
      ".config" # GNOME/dconf settings, GTK, mimeapps.list
      ".local/share/gnome-remote-desktop-rdp" # RDP password + TLS cert/key
    ];

    systemPackages = with pkgs; [
      sops
      age
      libfido2
      firefox
    ];
  };

  my = {
    # Old, comparatively slow CPU (2011 Sandy Bridge) — don't let nightly
    # auto-upgrade fall back to a multi-hour local compile if Attic ever misses.
    deploy.autoUpgrade = {
      enable = true;
      requireCache = true;
    };

    monitoring.node.enable = true;

    # Joins the unlock cluster as a 4th independent Tang server (alongside
    # nixos-nvme/core-pi/hass-pi/nasbook) — more fleet redundancy.
    services.tang.enable = true;

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Tang auto-unlock at boot — mandatory here, not optional: this host has
    # no physical keyboard/screen, ever, so a plain LUKS passphrase prompt
    # would hang forever with nobody able to answer it.
    #
    # `enable` is gated on the JWE existing rather than hardcoded true: the
    # JWE (nix-secrets/initrd/cryptroot_mac-mini.jwe) can only be generated
    # AFTER the real LUKS passphrase is set during the physical install
    # (disko), so it doesn't exist at the time this file is first committed.
    # Once it's generated — `scripts/generate-jwe.sh mac-mini`, same
    # passphrase used during disko format — this flips on automatically on
    # the next rebuild/redeploy; no further code change needed. Same pattern
    # hosts/nixos-nvme/hardware-boot.nix uses for its initrd SSH key.
    boot.clevis-initrd = {
      enable = builtins.pathExists (inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe");
      luksDevice = "mac_mini_crypt";
      secretFile = inputs.nix-secrets + "/initrd/cryptroot_mac-mini.jwe";
      fallbackMessage = "Tang still unreachable; falling back to initrd SSH (no physical console on this host)";
      # hostIp left null (default) — DHCP in initrd, no static IP assigned yet.
    };
  };

  # Initrd SSH fallback — same pattern as hosts/nixos-nvme/hardware-boot.nix.
  # mac-mini has zero physical keyboard/screen access, ever, so if Tang is
  # ever unreachable at boot the normal ask-password prompt would hang
  # forever with nobody able to answer it. This lets the passphrase be typed
  # in remotely instead. Gated on the key file existing, same convention as
  # clevis-initrd.enable above.
  boot = {
    initrd = {
      # tg3 (onboard Broadcom NetXtreme NIC) was missing from the initrd
      # entirely — neither Tang nor the initrd SSH fallback below can bring up
      # networking without it. Confirmed the hard way 2026-08-03: first reboot
      # after enabling both hung at an unreachable LUKS prompt with no network
      # in initrd at all, needing a one-off physical passphrase entry to
      # recover. Eager-load like nixos-nvme's e1000e (hardware-boot.nix).
      kernelModules = [ "tg3" ];

      network = {
        enable = true;
        ssh = {
          enable = builtins.pathExists (inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_mac-mini");
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_mac-mini" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_mac-mini" = lib.mkForce (
        inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_mac-mini"
      );
    };

    loader.systemd-boot = {
      enable = true;
      # Same cap orin-nano uses — an unpruned ESP fills up with stale
      # per-generation kernels/initrds over time.
      configurationLimit = 10;
    };
  };

  # Real x86 hardware (2011 Mac Mini, Sandy Bridge i5-2415M) — same reasoning
  # as nixos-nvme: microcode security/stability fixes, and redistributable
  # firmware in case the internal Broadcom Wi-Fi/Bluetooth ever gets used.
  # NOT required for the onboard tg3 Ethernet (BCM57765 is in the
  # 57765_PLUS chip group, which brings the link up without a firmware
  # blob) — Tang-unlock-in-initrd doesn't depend on this.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;

    # VAAPI for the eventual Zoom-recording container workload — a 2-core
    # CPU wants encode/decode offloaded to the iGPU. `intel-vaapi-driver`
    # (legacy i965), NOT `intel-media-driver` (iHD): the latter only
    # supports Broadwell+/Gen8+, this is Sandy Bridge/Gen6. Encode
    # support on Gen6 via i965 is known to be flaky on Linux (decode is
    # solid) — untested until the actual container exists; enabled now
    # so it's ready to try.
    graphics = {
      enable = true;
      extraPackages = with pkgs; [ intel-vaapi-driver ];
    };
  };

  # (services.fwupd is already on fleet-wide via core.nix — LVFS almost
  # certainly has nothing for this specific hardware anyway: Apple's own
  # Boot ROM firmware isn't LVFS-published, and the Samsung SATA SSD is
  # out of scope too — but it's already there for whatever's plugged in
  # later, no host-specific override needed.)
  #
  # Boot ROM confirmed current as of the 2026-08-02 High Sierra install
  # (133.0.0.0.0) — the last firmware Apple ever shipped for Macmini5,x.
  # Not upgradable further, and not LVFS-managed (see above), so if
  # third-party-OS boot flakiness ever shows up here, stale firmware is
  # ruled out as the cause.

  services = {
    # Fleet convention (rpi5-node.nix, nasbook, orin-nano): periodic TRIM
    # alongside disko's allowDiscards, not instead of it.
    fstrim.enable = true;

    # Join the NetBird mesh — same pattern as orin-nano/nasbook/core-pi/hass-pi
    # (modules/nixos/networking.nix netbird-autojoin, gated on netbird_setup_key
    # from secrets.nix).
    netbird.enable = true;

    # DNS was broken out of the box: modules/nixos/networking.nix defaults
    # networking.resolvconf.enable to true fleet-wide, and every OTHER host
    # overrides that (resolved.enable=true here like orin-nano, or forced off
    # like the rpi5 nodes) — mac-mini never got either override, so resolv.conf
    # pointed at a systemd-resolved stub (127.0.0.1) that was never enabled.
    resolved = {
      enable = true;
      settings.Resolve.FallbackDNS = "1.1.1.1 8.8.8.8";
      settings.Resolve.DNSSEC = "false";
    };
  };
  # Fixes network-routing.nix (fleet-wide via base.nix) silently targeting a
  # nonexistent "wlo1" (the my.network.externalInterface default) on every
  # boot/5min timer — harmless (the enforce-container-routes script has
  # `|| true`) but pointless without the real interface name.
  my.network.externalInterface = "enp2s0f0";

  # Static IP migration, stage 2 (cutover): DHCP lease (.70) retired, .16
  # (inventory.nix) is now the sole address with an explicit gateway. Stage 1
  # (ran first, verified .16 reachable/SSH-auth-working before cutting DHCP)
  # added .16 as a second address alongside DHCP as a safety net — no longer
  # needed now that .16 is confirmed. modules/flake/colmena.nix's targetHost
  # is updated to match in the same change.
  networking = {
    hostName = "mac-mini";

    # Paired with services.resolved above — see that comment for why this
    # override is needed on this host specifically.
    resolvconf.enable = lib.mkForce false;

    interfaces."enp2s0f0" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.0.16";
          prefixLength = 16;
        }
      ];
      # Wake-on-LAN: zero physical access (no keyboard/screen/case access
      # after it's mounted) makes remote power-on genuinely useful. Was
      # deliberately left unwired until the udev-assigned interface name was
      # known; enp2s0f0 is now confirmed.
      wakeOnLan.enable = true;
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "enp2s0f0";
    };
  };

  # Override the fleet-wide zstd zram default (core.nix): zstd's better
  # ratio costs more CPU per swap page than lz4, which matters more on
  # this 2-core CPU than on the rest of the fleet. 16GB RAM means this
  # host is unlikely to swap heavily anyway, so it's a marginal call —
  # revisit if the recording workload turns out to be swap-hungry.
  zramSwap.algorithm = lib.mkForce "lz4";

  # Stateless root (impermanence) — same pattern as modules/nixos/rpi5-node.nix
  # (shared by core-pi/hass-pi). disko.nix only declares the real, disk-backed
  # mounts (ESP, /nix/persist); the ephemeral tmpfs "/" and "/var" are a
  # NixOS-only concept with no disk backing, so they're declared here instead.
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  system.stateVersion = "25.11";
}
