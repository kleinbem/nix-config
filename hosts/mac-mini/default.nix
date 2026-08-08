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
  myInventory,
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
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.hermes
    inputs.nix-presets.nixosModules.hermes-juan
    inputs.nix-presets.nixosModules.persona-runtime
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

  # Same GNOME look/feel/keybindings/extensions martin uses on nixos-nvme
  # (theme, dash-to-panel, blur-my-shell, workspace shortcuts, etc.) —
  # base.nix already pulls in the home-manager NixOS module fleet-wide, so
  # this only needs a per-host opt-in. Deliberately NOT users/martin/home.nix
  # (nixos-nvme's full profile) — that pulls in dev tooling, pentesting,
  # vscode, syncthing, opencode, herdr, etc. that don't belong on this
  # single-purpose, no-console box. Just the shared dconf-settings module
  # (modules/home-manager/gnome.nix), same one nixos-nvme's home.nix imports.
  # ~/.config is already in this host's persistence list below, so dconf
  # state (extension enable/disable, any interactive tweaks) survives
  # reboots despite the tmpfs root.
  home-manager.users.${config.my.username} = {
    imports = [ "${self}/modules/home-manager/gnome.nix" ];
    modules.gnome.enable = true;

    # gnome.nix's org/gnome/settings-daemon/plugins/power (sleep-inactive-
    # ac-type, power-button-action = "interactive") lives under the exact
    # path programs.dconf.profiles.user.databases below locks with
    # lockAll = true — a plain user-db write there fails activation
    # outright ("non-writable keys"). Not just a technical workaround:
    # "interactive" would reintroduce the suspend bug that lock exists to
    # fix (this host has no display to show the confirm dialog on, so it
    # falls straight through to suspend — see the lock's own comment
    # further down). Defer entirely to the system-wide lock instead.
    dconf.settings."org/gnome/settings-daemon/plugins/power" = lib.mkForce { };

    home = {
      inherit (config.my) username;
      homeDirectory = config.my.home;
      stateVersion = "25.11";
    };
  };

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

    # Required for the monitoring container below: modules/nixos/
    # virtualisation.nix wraps its ENTIRE config (including
    # podman-network-cbr0, the service that actually creates the shared
    # cbr0 bridge every container — podman or nspawn — attaches to) in
    # `lib.mkIf cfg.enable`, the my.virtualisation.enable master switch.
    # podman.enable defaults to true on its own, but that default is inert
    # without this — confirmed live 2026-08-04: the monitoring container
    # failed to start with "Failed to add interface vb-monitoring to
    # bridge cbr0: No such device" because cbr0 had never been created on
    # this host (mac-mini never ran a container before). Same explicit
    # values rpi5-node.nix sets for core-pi/hass-pi.
    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
      lxc.enable = false;
    };

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
    #
    # subnet/hostAddress: this host's own slice of the fleet's container
    # network (modules/nixos/network-routing.nix's subnets map has a
    # matching "mac-mini" entry) — same pattern core-pi/nixos-nvme/hass-pi
    # use. Deliberately NOT sourced from inventory.nix's
    # hosts.mac-mini.ip (that field is colmena's real SSH deploy target,
    # currently the LAN IP — repointing it at this bridge address would
    # break deployment: colmena couldn't reach a brand-new bridge address
    # to deploy the very change that creates it, and cross-host routing to
    # it depends on a route that itself only exists after a successful
    # deploy). Hardcoded here instead, same as core-pi's own hostAddress.
    network = {
      externalInterface = "enp2s0f0";
      subnet = "10.85.50.0/24";
      hostAddress = "10.85.50.1";
    };

    containers = {
      # Moved from core-pi 2026-08-04: core-pi was genuinely RAM-constrained
      # (7.9GB, actively swapping under its existing container load —
      # grafana alone was ~226MB) while this host sat nearly idle (15GB
      # RAM, <1GB used). Verified before moving that CPU/network aren't a
      # downgrade either: same Gigabit link speed on both hosts' real
      # uplink, and a direct zstd -3 benchmark showed core-pi's Cortex-A76
      # is actually slightly *faster* per-core than this 2011 Sandy Bridge
      # chip (159 vs 142 MB/s) — so this move is purely about RAM/disk
      # headroom, not a performance upgrade. nodeTargets matches core-pi's
      # list plus this host's own bridge address (self-monitoring, wasn't
      # scraped before).
      monitoring = {
        enable = true;
        ip = "10.85.50.2/24";
        hostDataDir = "/var/lib/monitoring";
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.core-gateway.ip
          myInventory.hosts.ap-upstairs.ip
          myInventory.hosts.core-pi.ip
          myInventory.hosts.hass-pi.ip
          "10.85.50.1" # mac-mini itself (my.network.hostAddress above)
        ];
        githubMetrics.enable = false;
      };

      # Moved from hass-pi 2026-08-05: hass-pi's actual purpose (Home
      # Assistant + Zigbee/Z-Wave/BLE device integration, enableUSB/
      # enableBluetooth hardware pass-through) stays put — these five are
      # just AI chat/agent orchestration frontends with no local-hardware
      # dependency and no local inference (all route to litellm.internal ->
      # orin-nano's vLLM/Ollama, same as before), same profile as the
      # monitoring move above. IPs continue mac-mini's 10.85.50.0/24 slice
      # (.2 is monitoring above).
      open-webui = {
        enable = true;
        ip = "10.85.50.3/24";
        hostDataDir = "/var/lib/open-webui";
        memoryLimit = "2G";
      };

      # NOT openclaw (deliberately left on hass-pi): its pnpm-deps
      # fixed-output derivation has a hash mismatch against its pinned
      # upstream flake (github:openclaw/nix-openclaw) — confirmed
      # 2026-08-05 via a from-scratch build here, a genuine bug in that
      # external project's own lockfile, unrelated to this migration.
      # hass-pi's copy still works fine since it's running an
      # already-built/cached artifact (container-updater decouples
      # container updates from full host rebuilds) — only a *fresh*
      # build hits this. Move it once upstream fixes their lockfile.
      #
      # agent-zero disabled entirely (not just stopped): confirmed
      # 2026-08-05 that frdel/agent-zero:latest on Docker Hub currently
      # resolves to a plain Kali Linux base image, not the actual
      # application (no run_ui.py, no agent-zero code at all anywhere in
      # the image) — genuine upstream image drift, outside our control.
      # A manual `systemctl stop` doesn't survive reboot (still
      # enable=true, auto-starts and crash-loops trying the same broken
      # pull forever) — confirmed live after martin rebooted mac-mini.
      # Re-enable once upstream publishes a real image at this tag again.
      agent-zero = {
        enable = false;
        ip = "10.85.50.5/24";
        hostDataDir = "/var/lib/agent-zero";
        memoryLimit = "1G";
      };

      anythingllm = {
        enable = true;
        ip = "10.85.50.6/24";
        hostDataDir = "/var/lib/anythingllm";
        llmUrl = "https://litellm.internal";
        modelName = "google/gemma-2b"; # Aligned with Orin Nano backend in ai.nix
        memoryLimit = "2G";
      };

      hermes = {
        enable = true;
        ip = "10.85.50.7/24";
        hostDataDir = "/var/lib/hermes";
        memoryLimit = "2G";
        ollamaUrl = "https://litellm.internal/v1";
        secretsFile = config.sops.templates."hermes.env".path;
        discord.enable = true;
      };

      # Juan's persona worker — proof-of-concept for Hermes-as-worker with a
      # persona's own git identity, interactive-CLI-attachable via herdr
      # (see nix-presets/containers/hermes-juan.nix's addToSystemPackages
      # comment). A SEPARATE preset from `hermes` above, not an attrsOf
      # instance of it — attrsOf-of-submodule + the shared mkContainer
      # factory reproducibly triggers "infinite recursion encountered" when
      # evaluated via container-factory's catalogue construction (confirmed
      # even with a maximally minimal schema, unrelated to gitIdentity/
      # egress specifically — a real nixpkgs/flake-structure interaction,
      # not narrowed down further without real effort. See
      # hosts/container-factory/default.nix's comment on the same host).
      #
      # No Discord — this instance isn't reachable by chat yet, just a
      # `machinectl shell hermes-juan hermes` / herdr-attached session.
      # Real Gemini via hermes-agent's native adapter (not the local
      # LiteLLM gateway `hermes` above uses). Deployed + verified live
      # 2026-08-08 (real API round-trip via `hermes -z '...'`).
      #
      # model override: gemini-2.5-pro (juan's declared model in
      # personas.nix) has zero quota on kleinbem-ai's free tier — confirmed
      # live, Google gates Pro behind billing. gemini-flash-latest is what
      # actually works today; switch back to gemini-2.5-pro (or drop this
      # override to fall back to the preset default) once/if billing gets
      # enabled on the project.
      hermes-juan = {
        enable = true;
        ip = "10.85.50.8/24";
        hostDataDir = "/var/lib/hermes-juan";
        memoryLimit = "2G";
        model = "gemini/gemini-flash-latest";
        secretsFile = config.sops.templates."hermes-juan.env".path;
        gitIdentity = {
          name = "Juan González";
          email = "juan@kleinbem.dev";
          signingKeyFile = config.sops.secrets.juan_signing_key.path;
        };
      };

      # Generic, persona-agnostic worker — see nix-presets/containers/
      # persona-runtime.nix's header comment for the full "why one
      # container, not one per persona" reasoning (up to ~200 personas,
      # never concurrent, made hermes-juan's standing-container-per-
      # persona shape the wrong model). scripts/persona-invoke.sh writes
      # real identity into the three files below immediately before each
      # `machinectl start persona-runtime`, then shreds them after. Fixed
      # paths, root:root — the invoke script needs sudo/root to write
      # them anyway (same requirement as machinectl start/stop itself).
      #
      # hostDataDir is intentionally NOT in this host's persistence list
      # below (unlike hermes-juan's /var/lib/hermes-juan). It's a
      # host-side bind mount, so the container's own `ephemeral` rootfs
      # reset does NOT clear it — if it persisted across reboots, one
      # persona's session/memory state (hermes-agent's state.db) would
      # bleed into the next persona's context on this SAME shared
      # runtime. persona-invoke.sh wipes its contents before every
      # start, which already gives a clean slate per invocation; letting
      # it survive a reboot with stale content from whoever ran last
      # would only matter for the narrow case of a mid-session crash,
      # not worth the persistence-list entry.
      persona-runtime = {
        enable = true;
        ip = "10.85.50.9/24";
        hostDataDir = "/var/lib/persona-runtime-data";
        memoryLimit = "2G";
        secretsEnvFile = "/var/lib/persona-runtime/agent.env";
        gitConfigFile = "/var/lib/persona-runtime/gitconfig";
        signingKeyFile = "/var/lib/persona-runtime/signing-key";
      };
    };
  };

  # anythingllm runs podman nested inside its own ephemeral nspawn
  # container (my.containers.anythingllm above) — that container's own
  # root is tmpfs, capped small (~3.9G, systemd-nspawn's own default for
  # --ephemeral, not something my.containers exposes). Its image
  # consistently ran out of disk mid-unpack on every attempt — confirmed
  # live 2026-08-05, not a fluke. This gives podman's own storage dir
  # (/var/lib/containers, confirmed via /etc/containers/storage.conf
  # graphroot) a dedicated, generously-sized tmpfs mount instead of
  # resizing the whole ephemeral root — mac-mini has 15GB RAM with room to
  # spare. containers.<name>.tmpfs is the plain NixOS nixos-containers
  # option (nspawn's own --tmpfs=PATH:size=X), separate from and merging
  # fine alongside whatever my.containers.<name> (mkContainer) already
  # sets for the same container name. NOT agent-zero here anymore — it's
  # disabled entirely above (broken upstream image), and this attribute
  # alone (with my.containers.agent-zero.enable = false leaving the rest
  # of containers.agent-zero unset) breaks eval: "containers.agent-zero
  # .path was accessed but has no value defined."
  containers.anythingllm.tmpfs = [ "/var/lib/containers:size=8G" ];

  # All services.* for this host in one block too (same statix repeated-key
  # concern as my.* above).
  services = {
    # Moved from hass-pi 2026-08-05: not actually Home-Assistant-related
    # (network-wide DNS ad-blocking), just scope creep onto that box.
    # Confirmed with martin nothing depends on it being at hass-pi's IP
    # specifically (not wired into router/DHCP) before moving. port here
    # is the web admin UI (3000), not DNS (53) — doesn't conflict with
    # services.resolved below, which only binds loopback + the NetBird
    # interface, never the LAN-facing one.
    adguardhome = {
      enable = true;
      port = 3000;
      openFirewall = true;
    };

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

  # grdctl --system talks to gnome-remote-desktop-configuration.service over
  # the system bus, not a per-user session bus — this runs as a plain system
  # service, no gnome-session.target dependency.
  # All systemd.* for this host in one block (same statix repeated-key
  # concern as my.*/services.*/environment.* above).
  systemd = {
    services = {
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

    # Homarr dashboard's data dirs — moved from hass-pi 2026-08-05.
    tmpfiles.rules = [
      "d /var/lib/homarr 0755 root root - -"
      "d /var/lib/homarr/configs 0755 root root - -"
      "d /var/lib/homarr/icons 0755 root root - -"
      "d /var/lib/homarr/data 0755 root root - -"
    ];
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

  # All environment.* for this host in one block (same statix repeated-key
  # concern as my.*/services.* above — this used to be two separate spots).
  environment = {
    persistence."/nix/persist" = {
      # /home has no disk-backed mount of its own (disko.nix only declares
      # /nix and /nix/persist) — it lives under the tmpfs "/" declared near
      # the bottom of this file, so it's wiped every reboot by default.
      users.martin.directories = [
        ".mozilla" # Firefox profile
        ".config" # GNOME/dconf settings, GTK, mimeapps.list
      ];

      directories = [
        # /var/lib/gnome-remote-desktop is the dedicated system user's home
        # (modules created by services.gnome.gnome-remote-desktop.enable) —
        # where the system daemon's own grdctl --system state (credentials,
        # TLS cert) lives. Not in modules/nixos/persistence.nix's shared
        # list (that's for fleet-wide state, this is specific to this host
        # actually using the system RDP daemon) — needed here or
        # credentials regenerate every boot.
        "/var/lib/gnome-remote-desktop"

        # Monitoring container's actual state (VictoriaMetrics DB + Grafana
        # DB/dashboards) — moved from core-pi 2026-08-04, see the
        # my.containers.monitoring comment above for why. Same pattern
        # core-pi used for the same directory.
        "/var/lib/monitoring"

        # AI stack containers' state — moved from hass-pi 2026-08-05, see
        # the my.containers.open-webui comment above for why. Same
        # directories hass-pi used.
        "/var/lib/open-webui"
        "/var/lib/agent-zero"
        "/var/lib/anythingllm"
        "/var/lib/hermes"
        "/var/lib/hermes-juan"

        # Homarr + AdGuard Home — moved from hass-pi 2026-08-05 (not
        # HA-related, see the my.containers.open-webui / services block
        # comments above for the same reasoning). DynamicUser service
        # (AdGuard) needs the /var/lib/private path, not the /var/lib
        # symlink — same convention hass-pi used.
        "/var/lib/homarr"
        "/var/lib/private/AdGuardHome"
      ];
    };

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

  # Homarr dashboard — moved from hass-pi 2026-08-05, same reasoning as
  # AdGuard Home above (general-purpose start page, not HA-related).
  virtualisation.oci-containers.containers.homarr = {
    image = "ghcr.io/ajnart/homarr:latest";
    ports = [ "7575:7575" ];
    volumes = [
      "/var/lib/homarr/configs:/app/data/configs"
      "/var/lib/homarr/icons:/app/public/icons"
      "/var/lib/homarr/data:/data"
    ];
  };

  system.stateVersion = "25.11";
}
