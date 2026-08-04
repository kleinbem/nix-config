# mac-mini — Mid-2011 Mac Mini (Macmini5,x), Intel, real 64-bit EFI.
#
# Role: dedicated interactive box (no physical keyboard/mouse/screen — GUI
# access is remote-desktop only). First concrete use case: join/record Zoom
# calls from a container. Provisioned like orin-nano/core-pi/hass-pi — SSD
# wiped+installed via USB-SATA adapter (see .just/deployment.just
# mac-mini-install-usb), then moved internally.
{
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
    # firejail.nix is a separate file from desktop.nix, only pulled in
    # transitively via modules/nixos/default.nix's aggregator — which
    # mac-mini deliberately doesn't import wholesale (pulls in unrelated
    # things like kernel.nix/security/). my.desktop.gnome.enable alone does
    # NOT bring this in; without this explicit import,
    # programs.firejail.wrappedBinaries evaluates empty here even though
    # the option's own lib.mkIf condition is satisfied — confirmed via
    # `nix eval .#nixosConfigurations.mac-mini.config.programs.firejail.wrappedBinaries`.
    "${self}/modules/nixos/firejail.nix"

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

  # All my.* fleet options for this host live in one block (statix flags
  # repeated top-level keys — this used to be three separate my.* spots).
  my = {
    # Remote desktop: this host's whole reason for existing (see top-of-file
    # comment) is GUI access with zero physical keyboard/screen/console ever
    # attached. Was Wayland (sway) + wayvnc + noVNC (bespoke systemd services
    # driving a headless wlroots compositor by hand — see git history for that
    # setup); replaced with real GNOME (my.desktop.gnome.enable, the same
    # fleet-wide module nixos-nvme uses) via GNOME Remote Desktop, which is
    # the module's own supported answer to "no physical display ever
    # attached" rather than a hand-rolled runtime dir + WLR_BACKENDS=headless
    # trick. See the NOT autologin comment further down for the actual
    # login/RDP architecture — it isn't the simple "headless daemon on
    # autologin" this paragraph originally described.
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
    # NOT autologin (reverted 2026-08-04, see git history for the autologin +
    # headless-only version this replaced): gnome-remote-desktop's --headless
    # daemon is designed to run standalone, as the only compositor on the
    # machine — layering it on top of an already-running GDM autologin
    # session consistently failed with "Session creation inhibited" on every
    # connection attempt (reproduced with both GNOME Connections and
    # wlfreerdp, including on a freshly-restarted daemon's very first
    # attempt — not stale state). The architecture GNOME actually supports
    # for "headless box, RDP for GUI access" is RDP straight into the GDM
    # login screen itself (gnome-remote-desktop.service, System daemon,
    # WantedBy=graphical.target — was sitting inactive this whole time) with
    # a real interactive login, then GDM's own handover mechanism
    # (gnome-remote-desktop-handover.service, packaged, not authored here)
    # bridges the RDP connection into the resulting session. defaultSession
    # still applies to whatever session GDM starts after that login.
    desktop.gnome.enable = true;

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

    # Fixes network-routing.nix (fleet-wide via base.nix) silently targeting a
    # nonexistent "wlo1" (the my.network.externalInterface default) on every
    # boot/5min timer — harmless (the enforce-container-routes script has
    # `|| true`) but pointless without the real interface name.
    network.externalInterface = "enp2s0f0";
  };

  # All services.* for this host in one block too (same statix repeated-key
  # concern as my.* above).
  services = {
    # Whatever session GDM starts after a successful login (see the NOT
    # autologin comment above for the actual login/RDP architecture).
    displayManager.defaultSession = "gnome";

    gnome.gnome-remote-desktop.enable = true;

    # Defense-in-depth alongside the dconf lock further down: logind's OWN
    # power-key handling (independent of GNOME's gsd-media-keys, e.g. before
    # a session exists to claim it) also gets set to ignore, so there's no
    # path — GNOME session up or not — where a power-button signal results
    # in suspend.
    logind.settings.Login.HandlePowerKey = "ignore";

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

  # /var/lib/gnome-remote-desktop is the dedicated system user's home
  # (modules created by services.gnome.gnome-remote-desktop.enable) — where
  # the system daemon's own grdctl --system state (credentials, TLS cert)
  # lives. Not in modules/nixos/persistence.nix's shared list (that's for
  # fleet-wide state, this is specific to this host actually using the
  # system RDP daemon), so add it here or credentials regenerate every boot.
  environment.persistence."/nix/persist".directories = [
    "/var/lib/gnome-remote-desktop"
  ];

  # grdctl --system talks to gnome-remote-desktop-configuration.service over
  # the system bus, not a per-user session bus — this runs as a plain system
  # service, no gnome-session.target dependency.
  systemd.services = {
    gnome-remote-desktop-system-rdp-setup = {
      description = "Provision GNOME Remote Desktop (system/login-screen RDP) credentials + TLS cert";
      after = [ "gnome-remote-desktop-configuration.service" ];
      requires = [ "gnome-remote-desktop-configuration.service" ];
      before = [ "gnome-remote-desktop.service" ];
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # NOT User = "gnome-remote-desktop" (tried first, wrong): confirmed
        # live 2026-08-04 via direct comparison — `sudo -u gnome-remote-desktop
        # grdctl --system rdp set-credentials ...` (this service's exact prior
        # execution context) reports exit 0 but silently writes nothing;
        # `pkexec --user gnome-remote-desktop grdctl ...` run AS ROOT actually
        # writes credentials.ini correctly. grdctl's own internal pkexec call
        # apparently doesn't correctly escalate when the invoking user is
        # already the target user — needs a real privilege transition, not a
        # same-user one. Running this service as root (systemd's default,
        # hence no User= here) lets grdctl's own pkexec do that transition
        # properly, matching the working manual invocation.
      };
      # Confirmed live 2026-08-04: grdctl --system shells out to pkexec (the
      # security.polkit setuid wrapper at /run/wrappers/bin, already enabled
      # via services.gnome.gnome-remote-desktop's own module) to actually
      # configure the system daemon. Plain systemd services get systemd's
      # own minimal built-in PATH, not the full system profile — same
      # PATH-missing-pkexec/dbus-daemon class of bug the old (now-removed)
      # sway-headless service hit for dbus-daemon specifically.
      environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      script = ''
        set -euo pipefail
        umask 077
        state="/var/lib/gnome-remote-desktop/rdp-provisioning"
        mkdir -p "$state"

        if [ ! -f "$state/password" ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 18 > "$state/password"
          echo "Generated a new GNOME Remote Desktop (system/login-screen RDP) password for martin — save it now: $(cat "$state/password")"
        fi

        if [ ! -f "$state/tls.crt" ] || [ ! -f "$state/tls.key" ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
            -subj "/CN=mac-mini" \
            -keyout "$state/tls.key" -out "$state/tls.crt" 2>/dev/null
        fi

        grdctl="${pkgs.gnome-remote-desktop}/bin/grdctl"
        "$grdctl" --system rdp set-tls-cert "$state/tls.crt"
        "$grdctl" --system rdp set-tls-key "$state/tls.key"
        "$grdctl" --system rdp set-credentials martin "$(cat "$state/password")"
        "$grdctl" --system rdp enable
      '';
    };

    # Confirmed live 2026-08-04: unlike gnome-remote-desktop-system-rdp-setup
    # (which explicitly declares wantedBy itself), the PACKAGED
    # gnome-remote-desktop.service's own [Install] WantedBy=graphical.target
    # never actually got linked — `ls /etc/systemd/system/graphical.target.wants/`
    # had no entry for it. NixOS does not appear to auto-process a
    # systemd.packages-provided unit's [Install] section into that symlink;
    # it needs an explicit wantedBy from a systemd.services.<name> override
    # here to actually get created declaratively. This is also very likely
    # why `grdctl --system rdp enable` failed with EROFS trying to write
    # that exact symlink itself at runtime — NixOS's /etc is immutable, so
    # nothing (grdctl included) can create it there at runtime; it has to be
    # done at build/activation time via this option instead.
    gnome-remote-desktop = {
      after = [ "gnome-remote-desktop-system-rdp-setup.service" ];
      requires = [ "gnome-remote-desktop-system-rdp-setup.service" ];
      wantedBy = [ "graphical.target" ];
    };
  };

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
  #
  # lockAll = true (not a plain default): dconf's own precedence puts the
  # user's personal database (user-db:user, ~/.config/dconf/user) ahead of
  # system defaults — enableUserDb defaults to true — so a plain default
  # here can be silently shadowed by anything that ever writes an explicit
  # value into the user db (a GNOME component initializing/migrating
  # settings, gnome-control-center's Power panel being opened, etc.).
  # Locking is mandatory-enforcement instead: no per-user write can
  # override it. Appropriate here because there's no legitimate reason for
  # this specific value to ever differ on this single-purpose, no-console
  # host — unlike nixos-nvme, where a real human might reasonably want to
  # change power settings via the GUI.
  # power-button-action added after idle-suspend locking turned out NOT to
  # be the whole story: confirmed via /var/log/journal (persisted through
  # impermanence, modules/nixos/persistence.nix) that the box suspended
  # again 26 minutes into a normal running session, with NO idle-timeout
  # involved at all — systemd-logind logged "Power key pressed short" /
  # "suspend requested from client ... ('.gsd-media-keys')". desktop.nix's
  # shared power-button-action = "interactive" (meant to show a confirm
  # dialog) has no display to show that dialog on here, so it appears to
  # fall through straight to suspend. Whether the button press itself was
  # a genuine spurious ACPI signal (a known quirk class on older Apple
  # hardware under Linux) or something else, the fix is the same either
  # way: this box has no legitimate reason to ever honor a power-button
  # suspend, since resume-from-sleep is already confirmed broken on this
  # hardware (see mac-mini-wake's doc).
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing"; # no battery on this hardware, kept for consistency
        power-button-action = "nothing";
      };
      lockAll = true;
    }
  ];

  # STILL not the whole story: confirmed via /var/log/journal that both the
  # earlier power-button suspend AND a later idle-looking suspend were
  # actually requested by unit `user@60578.service` — that's gdm-greeter,
  # NOT martin (uid 1000). GDM keeps a greeter session alive on the seat
  # even after autologin succeeds (`loginctl list-sessions` shows both a
  # martin session and a gdm-greeter session running the whole time), and
  # that greeter session runs its OWN gsd-power/gsd-media-keys instance,
  # governed by the separate "gdm" dconf profile (desktop.nix, currently
  # only sets org/gnome/login-screen keys) — completely untouched by the
  # programs.dconf.profiles.user lock above, which only covers martin's
  # actual session. Every dconf.databases entry for a profile concatenates
  # (list-type option), so this adds to desktop.nix's existing gdm database
  # rather than replacing it.
  programs.dconf.profiles.gdm.databases = [
    {
      settings."org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing";
        power-button-action = "nothing";
      };
      lockAll = true;
    }
  ];

  # NOT headless mode (removed 2026-08-04, see git history): gnome-remote-
  # desktop --headless goes through mutter's XDG remote-desktop PORTAL API,
  # which — per upstream (gitlab.gnome.org/GNOME/gnome-remote-desktop
  # issue #16; matches https://bugs.launchpad.net/ubuntu/+source/gnome-
  # remote-desktop/+bug/1936261) — refuses to create or restore a screencast
  # session whenever the session is considered locked. Confirmed live: this
  # is not specific to autologin — the packaged gnome-remote-desktop-headless
  # unit is WantedBy=gnome-session.target, which is NOT scoped to any one
  # user; GDM's greeter is itself a real gnome-session, so this same unit
  # was also running under the gdm-greeter account this whole time, and hit
  # the IDENTICAL "Session creation inhibited" error there too — ruling out
  # "layered on an existing autologin session" as the cause. The system
  # daemon (gnome-remote-desktop.service, above) uses mutter's privileged
  # remote-desktop API instead of the portal, which upstream documents as
  # exactly the intended fix for "works at the GDM login screen, never
  # inhibited by the lock shield." Disabling headless entirely — it was
  # also actively harmful here: its Conflicts=gnome-remote-desktop.service
  # meant it was stopping the system daemon and claiming port 3389 for
  # itself (the portal-based, always-inhibited path) every time it started.
  systemd.user.services.gnome-remote-desktop-headless.enable = false;

  environment = {
    # /home has no disk-backed mount of its own (disko.nix only declares
    # /nix and /nix/persist) — it lives under the tmpfs "/" declared near
    # the bottom of this file, so it's wiped every reboot by default.
    persistence."/nix/persist".users.martin.directories = [
      ".mozilla" # Firefox profile
      ".config" # GNOME/dconf settings, GTK, mimeapps.list
    ];

    systemPackages = with pkgs; [
      sops
      age
      libfido2
      # NOT firefox here: my.desktop.gnome.enable (above) pulls in
      # modules/nixos/firejail.nix, which already wraps a sandboxed
      # firefox-beta under the plain "firefox" binary name — same as
      # nixos-nvme. An explicit plain pkgs.firefox here would shadow that
      # wrapper; confirmed live 2026-08-03 that it was doing exactly that
      # (firefox resolved to the unsandboxed store path) before this was
      # removed — leftover from before this host ran GNOME at all.
    ];
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
