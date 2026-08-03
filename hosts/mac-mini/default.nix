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
  # attached. Wayland (sway), not X11 — xrdp was considered first but it only
  # speaks X11 (drives xorgxrdp/Xvnc, no compositor support at all), and a
  # real wlroots compositor + wayvnc is the modern equivalent without that
  # legacy dependency.
  #
  # Auth: wayvnc's only auth backend is a PAM username+password check, which
  # would be this fleet's first password-gated remote-access surface (every
  # other host is FIDO2/Yubikey pubkey-only, headless.nix sets
  # PasswordAuthentication=false and martin has no password hash here at
  # all). Same call already made for NetBird's keyless SSH (reverted
  # fleet-wide for being weaker auth than pubkey SSH). So wayvnc binds
  # loopback-only and is NOT reachable from LAN/NetBird directly — reach it
  # via `ssh -L 5900:localhost:5900 mac-mini` (FIDO2/Yubikey pubkey, the
  # fleet's real trust mechanism) then point a VNC client at localhost:5900.
  # No firewall rule needed: nothing is listening on a routable interface.
  #
  # Audio: the RFB protocol wayvnc speaks has no audio channel at all (never
  # has, in any VNC implementation) — so sound needs its own path, riding the
  # same SSH pubkey trust rather than a new listening service. PipeWire +
  # WirePlumber below give the sway session somewhere to send audio, and
  # pipewire-null-sink-headless (further down) declares a virtual sink with
  # a real monitor port and makes it the default — WirePlumber's own
  # fallback ("Dummy Output") has no monitor at all on this host, since
  # there's no real audio hardware. To actually hear it on the client, pull
  # it over the same SSH connection, using parec (not pw-record — that's
  # native-protocol only and can't see a pulse-compat monitor by name):
  #   ssh mac-mini parec --device=headless_sink.monitor --format=s16le --rate=48000 --channels=2 \
  #     | pw-play --format=s16 --rate=48000 --channels=2 -
  # (client side needs its own pipewire install for pw-play). On-demand, not
  # a standing tunnel — matches the ssh -L step above rather than adding an
  # always-on audio daemon.
  programs.sway = {
    enable = true;
    # XWayland stays on (module default) for GUI apps (e.g. the eventual
    # Zoom-recording container) that don't speak native Wayland.
  };

  # Full config override, not the stock sway config programs.sway ships
  # (mkOptionDefault priority, so a plain assignment here wins). Tuned for
  # this box's actual situation: driven entirely over VNC from another
  # machine's keyboard, no physical display to size for, dark-mode
  # preference.
  environment = {
    etc."sway/config".text = ''
      # Mod4 (Super) risks being intercepted by the host GNOME session on
      # whatever machine you're VNC-ing in from before it ever reaches this
      # compositor. Alt passes through VNC clients far more reliably.
      set $mod Mod1
      set $term foot
      set $menu wmenu-run

      # wlroots' headless backend defaults to a cramped 1280x720 virtual
      # output — there's no physical monitor to size against, so just pick
      # something comfortable to view over VNC.
      output HEADLESS-1 resolution 1920x1080

      output * bg #000000 solid_color

      # GTK apps (Firefox, pcmanfm) pick up dark mode from $GTK_THEME, set on
      # the sway-headless systemd service below.

      gaps inner 8
      default_border pixel 2

      # Mouse-first setup: every window floats by default instead of tiling,
      # with a real titlebar to grab (default_floating_border normal, not
      # pixel) — drag the titlebar to move, drag an edge/corner to resize,
      # no keyboard modifier required for either. floating_modifier below is
      # a fallback (hold $mod to drag from anywhere in the window body), not
      # the primary way to move things.
      for_window [app_id=".*"] floating enable
      for_window [class=".*"] floating enable
      default_floating_border normal

      font pango:sans 10

      floating_modifier $mod normal

      # Scroll over empty desktop to switch workspaces; right-click empty
      # desktop for the app launcher — both fire only on bare background,
      # never stealing scroll/right-click from an actual application window.
      bindsym button3 exec $menu
      bindsym button4 workspace prev
      bindsym button5 workspace next
      bindsym $mod+Return exec $term
      bindsym $mod+Shift+q kill
      bindsym $mod+d exec $menu
      bindsym $mod+Shift+c reload
      bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit sway (ends the VNC session)?' -B 'Yes, exit sway' 'swaymsg exit'

      bindsym $mod+Left focus left
      bindsym $mod+Down focus down
      bindsym $mod+Up focus up
      bindsym $mod+Right focus right
      bindsym $mod+Shift+Left move left
      bindsym $mod+Shift+Down move down
      bindsym $mod+Shift+Up move up
      bindsym $mod+Shift+Right move right

      bindsym $mod+1 workspace number 1
      bindsym $mod+2 workspace number 2
      bindsym $mod+3 workspace number 3
      bindsym $mod+4 workspace number 4
      bindsym $mod+5 workspace number 5
      bindsym $mod+Shift+1 move container to workspace number 1
      bindsym $mod+Shift+2 move container to workspace number 2
      bindsym $mod+Shift+3 move container to workspace number 3
      bindsym $mod+Shift+4 move container to workspace number 4
      bindsym $mod+Shift+5 move container to workspace number 5

      bindsym $mod+h splith
      bindsym $mod+v splitv
      bindsym $mod+s layout stacking
      bindsym $mod+w layout tabbed
      bindsym $mod+e layout toggle split
      bindsym $mod+f fullscreen
      bindsym $mod+Shift+space floating toggle
      bindsym $mod+space focus mode_toggle

      bindsym $mod+Shift+minus move scratchpad
      bindsym $mod+minus scratchpad show

      mode "resize" {
          bindsym Left resize shrink width 10px
          bindsym Down resize grow height 10px
          bindsym Up resize shrink height 10px
          bindsym Right resize grow width 10px
          bindsym Return mode "default"
          bindsym Escape mode "default"
      }
      bindsym $mod+r mode "resize"

      # No idle lock, deliberately: this box has no physical screen to
      # protect (headless, VNC-only), and the real access gate is the
      # loopback-only wayvnc + SSH tunnel, not anything inside the session.
      # swayidle/swaylock are installed (programs.sway.extraPackages default)
      # but intentionally not wired up here.

      client.focused          #4c7899 #000000 #ffffff #2e9ef4   #000000
      client.focused_inactive #333333 #000000 #ffffff #484e50   #000000
      client.unfocused        #333333 #000000 #888888 #292d2e   #000000
      client.urgent           #2f343a #900000 #ffffff #900000   #900000
      client.background       #000000

      bar {
          position top
          status_command while date +'%Y-%m-%d %X'; do sleep 1; done
          colors {
              background #000000
              statusline #ffffff
              focused_workspace  #4c7899 #285577 #ffffff
              inactive_workspace #000000 #000000 #888888
          }
      }

      include /etc/sway/config.d/*
    '';

    # /home has no disk-backed mount of its own (disko.nix only declares
    # /nix and /nix/persist) — it lives under the tmpfs "/" declared near
    # the bottom of this file, so it's wiped every reboot by default. The
    # fleet-wide persistence.nix only keeps shell history for hosts other
    # than nixos-nvme (whose /home is a real, separate partition) —
    # mac-mini is the first host in the fleet running GUI apps that
    # actually need real per-user state, so there's no existing pattern to
    # inherit here. Without this, Firefox's profile (bookmarks/history/
    # logins/extensions) and pcmanfm/GTK settings (e.g. the dark theme)
    # would reset every boot.
    persistence."/nix/persist".users.martin.directories = [
      ".mozilla" # Firefox profile
      ".config" # pcmanfm bookmarks, GTK/dconf-less settings, mimeapps.list
    ];

    systemPackages = with pkgs; [
      sops
      age
      libfido2

      # Sway session extras — programs.sway.extraPackages only covers the
      # bare minimum (terminal, launcher, lock/idle); this rounds it out
      # into an actually usable remote desktop over wayvnc.
      firefox
      pcmanfm # lightweight GTK file manager, fits the minimal setup better
      # than Nautilus/Thunar's heavier dependency chains
      wl-clipboard # wl-copy/wl-paste
      slurp # region-select for the grim screenshot tool already in
      # programs.sway.extraPackages
      swappy # quick screenshot annotation

      pipewire # pw-record/pw-play, for the ssh-piped audio one-liner above
    ];
  };

  systemd.services = {
    sway-headless = {
      description = "Headless Sway compositor (no physical display) for remote desktop";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "martin";
        Group = "users";
        # Self-contained runtime dir — deliberately not /run/user/<uid>, the
        # one logind would give a systemd --user session (martin does have
        # linger=true set fleet-wide, users/martin/nixos.nix, so that dir
        # does exist here too). Using a plain system service instead keeps
        # sway/wayvnc/pipewire independent of user@<uid>.service's own
        # startup ordering, and gives them one shared runtime dir instead of
        # needing to agree on logind's.
        RuntimeDirectory = "sway-headless";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${config.programs.sway.package}/bin/sway";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      environment = {
        # No physical GPU output ever attached — wlroots' headless backend
        # creates a virtual output instead of requiring real DRM/KMS access.
        WLR_BACKENDS = "headless";
        WLR_LIBINPUT_NO_DEVICES = "1";
        XDG_RUNTIME_DIR = "/run/sway-headless";
        WAYLAND_DISPLAY = "wayland-1";
        XDG_SESSION_TYPE = "wayland";
        # GTK apps (Firefox, pcmanfm) launched inside this session inherit
        # this — forces dark mode without needing a full gsettings/dconf
        # stack, which this minimal setup doesn't have.
        GTK_THEME = "Adwaita:dark";
        # System services get systemd's own minimal built-in PATH (coreutils/
        # findutils/systemd bin dirs only), NOT /run/current-system/sw/bin —
        # that's a login-shell/profile thing. The wrapped sway binary shells
        # out to `dbus-run-session`, which then needs `dbus-daemon` on PATH;
        # without this it fails with "No such file or directory" (exit 127).
        # Confirmed the hard way on first deploy 2026-08-03: sway-headless
        # crash-looped every 5s until this was added. /run/wrappers/bin is
        # for setuid wrappers sway or its children might need too.
        PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      };
    };

    wayvnc = {
      description = "wayvnc VNC server for the headless Sway session (loopback only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "sway-headless.service" ];
      requires = [ "sway-headless.service" ];
      serviceConfig = {
        Type = "simple";
        User = "martin";
        Group = "users";
        ExecStart = "${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 5900";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/sway-headless";
        WAYLAND_DISPLAY = "wayland-1";
      };
    };

    # Deliberately not services.pipewire.enable: that module wires PipeWire
    # as systemd --user units, which live under logind's /run/user/<uid> —
    # a different runtime dir than the /run/sway-headless this whole session
    # already uses (see the runtime-dir comment on sway-headless above).
    # Running PipeWire as plain system services pointed at the same
    # /run/sway-headless keeps everything — Wayland socket, wayvnc, audio —
    # in one runtime dir any app spawned inside the sway session can find.
    # (The module's other alternative, services.pipewire.systemWide, is a
    # different thing: a separate "pipewire" system user shared across all
    # users, which upstream itself advises against — not what's needed for a
    # single-user box.)
    pipewire-headless = {
      description = "PipeWire media server for the headless Sway session";
      wantedBy = [ "multi-user.target" ];
      after = [ "sway-headless.service" ];
      requires = [ "sway-headless.service" ];
      serviceConfig = {
        Type = "simple";
        User = "martin";
        Group = "users";
        ExecStart = "${pkgs.pipewire}/bin/pipewire -c ${pkgs.pipewire}/share/pipewire/pipewire.conf";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      environment.XDG_RUNTIME_DIR = "/run/sway-headless";
    };

    # Chromium/Firefox (and most Electron apps, e.g. Zoom) talk libpulse, not
    # native PipeWire — this compat server is what actually catches their
    # audio output. Socket lands at $XDG_RUNTIME_DIR/pulse/native, same dir
    # every app in the sway session already has as XDG_RUNTIME_DIR, so
    # nothing extra needs pointing at it.
    pipewire-pulse-headless = {
      description = "PipeWire PulseAudio-compat server for the headless Sway session";
      wantedBy = [ "multi-user.target" ];
      after = [ "pipewire-headless.service" ];
      requires = [ "pipewire-headless.service" ];
      serviceConfig = {
        Type = "simple";
        User = "martin";
        Group = "users";
        ExecStart = "${pkgs.pipewire}/bin/pipewire-pulse -c ${pkgs.pipewire}/share/pipewire/pipewire-pulse.conf";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      environment.XDG_RUNTIME_DIR = "/run/sway-headless";
    };

    wireplumber-headless = {
      description = "WirePlumber session manager for the headless PipeWire instance";
      wantedBy = [ "multi-user.target" ];
      after = [ "pipewire-headless.service" ];
      requires = [ "pipewire-headless.service" ];
      serviceConfig = {
        Type = "simple";
        User = "martin";
        Group = "users";
        ExecStart = "${pkgs.wireplumber}/bin/wireplumber";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      environment.XDG_RUNTIME_DIR = "/run/sway-headless";
    };

    # No real audio hardware exists on this host, so WirePlumber's own
    # fallback ("Dummy Output") has no monitor port at all — confirmed live
    # via `wpctl status`/`pactl list short sources` (empty). Without a
    # monitor there's nothing for the ssh-piped pw-record/parec one-liner
    # (top-of-file Audio comment) to capture. This declares a proper null
    # sink with a real monitor instead, and makes it the default so anything
    # in the sway session actually routes there. Oneshot + RemainAfterExit:
    # runs once per boot, not restarted continuously; the sink-exists check
    # keeps it idempotent if the service ever IS manually restarted (loading
    # module-null-sink twice would otherwise create a duplicate sink).
    pipewire-null-sink-headless = {
      description = "Create the headless virtual audio sink (WirePlumber's own fallback has no monitor port)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "pipewire-pulse-headless.service"
        "wireplumber-headless.service"
      ];
      requires = [
        "pipewire-pulse-headless.service"
        "wireplumber-headless.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "martin";
        Group = "users";
        ExecStart = pkgs.writeShellScript "pipewire-null-sink-setup" ''
          set -euo pipefail
          if ! ${pkgs.pulseaudio}/bin/pactl list short sinks | grep -q headless_sink; then
            ${pkgs.pulseaudio}/bin/pactl load-module module-null-sink \
              sink_name=headless_sink sink_properties=device.description=Headless_Sink
          fi
          ${pkgs.pulseaudio}/bin/pactl set-default-sink headless_sink
        '';
      };
      environment.XDG_RUNTIME_DIR = "/run/sway-headless";
    };
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
