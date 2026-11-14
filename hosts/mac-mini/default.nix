# mac-mini: Mid-2011 Mac Mini (Macmini5,x), Intel, real 64-bit EFI.
# Headless (no keyboard or screen), GUI only over remote desktop. Installed
# over a USB-SATA adapter with `just deployment::mac-mini-install-usb`.
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  myInventory,
  secretFile,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";

  # Persona identity (full-name/email) for git authorship, read live from
  # kleinbem-secrets/personas/contact.nix so it can't drift. That file is
  # plain Nix: the values go public with the first commit anyway.
  personasView = import "${self}/lib/personas.nix" {
    inherit lib;
    contact = import "${inputs.kleinbem-secrets}/personas/contact.nix";
  };
  # Which persona names get their own invocable persona-runtime slot —
  # currently the two with a tool wired into that container's toolSpecs
  # (gemini-cli, claude-code). Extend as more tools get wired in there.
  invocablePersonaNames = [
    "juan-gonzalez"
    "michael-gruber"
  ];
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
    "${self}/modules/nixos/pull-deploy-node.nix"

    "${self}/users/martin/nixos.nix"
    inputs.nix-gantry.nixosModules.host
    inputs.nix-gantry.nixosModules.host-persistence
    inputs.nix-gantry.nixosModules.updater
    "${self}/modules/nixos/desktop.nix"
    # Normally pulled in by modules/nixos/default.nix, which this host doesn't
    # import; my.desktop.gnome.enable alone leaves the firejail wrappers empty.
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
    inputs.nix-presets.nixosModules.persona-runtime
    inputs.nix-presets.nixosModules.herdr-remote-client
    # Discord/Element/Signal in nixpak sandboxes — successor to the
    # firejail.nix wrappers imported above, app by app.
    inputs.nix-presets.nixosModules.sandboxed-apps
  ];

  # Same fleet-wide key set as every other host (modules/nixos/keys.nix).
  # headless.nix only creates the user; each host authorizes its own keys.
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];
  # No root keys: PermitRootLogin is prohibit-password (security/ssh.nix),
  # and without an authorized key that means no root login at all. Every
  # remote task goes through martin + sudo (the per-command allowlist in
  # security/sudo.nix, pam_rssh touch key for the rest).

  # Same GNOME setup as nixos-nvme, but only the shared gnome.nix module, not
  # users/martin/home.nix (dev tooling that doesn't belong on this box).
  # ~/.config is persisted below, so dconf state survives the tmpfs root.
  home-manager.users.${config.my.username} = {
    imports = [ "${self}/modules/home-manager/gnome.nix" ];
    modules.gnome.enable = true;

    # The system-wide dconf lock below owns this path: a user-db write there
    # fails activation ("non-writable keys"), and gnome.nix's "interactive"
    # power button would bring back the suspend bug.
    dconf.settings."org/gnome/settings-daemon/plugins/power" = lib.mkForce { };

    home = {
      inherit (config.my) username;
      homeDirectory = config.my.home;
      stateVersion = "25.11";

      # Chrome, declared directly since this host skips the nix-presets
      # desktop bundle. Not firejailed (see modules/nixos/firejail.nix).
      packages = [
        (pkgs.google-chrome.override {
          commandLineArgs = "--enable-features=WaylandWindowDecorations";
        })
      ];
    };

    # Chrome's Wayland app_id is "google-chrome-stable" but upstream ships
    # google-chrome.desktop; without a matching desktop file the dash favorite
    # and window grouping break.
    xdg.desktopEntries."google-chrome-stable" = {
      name = "Google Chrome";
      genericName = "Web Browser";
      exec = "google-chrome-stable %U";
      icon = "google-chrome";
      terminal = false;
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeType = [
        "text/html"
        "application/xhtml+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      settings = {
        StartupNotify = "true";
        StartupWMClass = "google-chrome-stable";
      };
    };
  };

  # All my.* options in one block (statix flags repeated top-level keys).
  my = {
    # External dead-man's switch (modules/nixos/heartbeat.nix): <host>-alive
    # every 5 min + a ping per backup job; missing pings alert from
    # healthchecks.io, outside the fleet. Always-on hosts only.
    heartbeat.enable = true;
    # GUI access over RDP into the GDM login screen; GDM hands the session over after login.
    # Not autologin: grd --headless on top of an autologin session fails with
    # "Session creation inhibited". RDP is password-only, so it stays off the firewall:
    # reach it with `ssh -L 3389:localhost:3389 mac-mini`.
    desktop.gnome.enable = true;
    desktop.sandboxedApps.enable = true;

    # comin follows the production branch. requireCache keeps the 2011 Sandy
    # Bridge from ever compiling a closure locally.
    deploy = {
      autoUpgrade.enable = false;
      comin = {
        enable = true;
        requireCache = true;
      };
    };

    monitoring.node.enable = true;

    # my.virtualisation.enable gates podman-network-cbr0, which creates the
    # cbr0 bridge every container attaches to; podman.enable alone is inert.
    # Without it containers fail with "Failed to add interface ... to bridge cbr0".
    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
    };

    # Joins the unlock cluster as a 4th independent Tang server (alongside
    # nixos-nvme/core-pi/hass-pi/nasbook) — more fleet redundancy.
    services.tang.enable = true;

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # Fleet backups (modules/nixos/backup.nix); tang, open-webui and stalwart
    # register their own items. Needs backup_r2_rclone_config in
    # nix/per-host/mac-mini.yaml.
    backup.enable = true;

    # Tang auto-unlock is mandatory here: with no keyboard or screen a LUKS
    # prompt would hang forever. Gated on the JWE existing, which can only be
    # made after install (`scripts/generate-jwe.sh mac-mini`).
    boot.clevis-initrd = {
      enable = builtins.pathExists (secretFile "initrd/cryptroot_mac-mini.jwe");
      luksDevice = "mac_mini_crypt";
      secretFile = secretFile "initrd/cryptroot_mac-mini.jwe";
      fallbackMessage = "Tang still unreachable; falling back to initrd SSH (no physical console on this host)";
      # hostIp left null (default) — DHCP in initrd, no static IP assigned yet.
    };

    # externalInterface: network-routing.nix otherwise targets the default
    # "wlo1", which doesn't exist here.
    network.externalInterface = "enp2s0f0";

    containers = {
      # Here rather than core-pi for RAM headroom (core-pi swapped, this host
      # has 15GB mostly idle).
      monitoring = {
        enable = true;
        ip = "10.85.50.2/24";
        hostDataDir = "/var/lib/monitoring";
        # Rendered by secrets.nix once ntfy_monitoring_password exists in
        # nix/per-host/mac-mini.yaml. Until then alerts go to the preset's
        # guessable default topic "alerts".
        ntfy.authConfigFile =
          if config.sops.templates ? "alertmanager-ntfy.yml" then
            config.sops.templates."alertmanager-ntfy.yml".path
          else
            null;
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.core-gateway.ip
          myInventory.hosts.ap-upstairs.ip
          myInventory.hosts.core-pi.ip
          myInventory.hosts.hass-pi.ip
          "10.85.50.1" # mac-mini itself (my.network.hostAddress above)
        ];
        githubMetrics.enable = false;
        # GF_SECURITY_SECRET_KEY, once grafana_secret_key is in sops (secrets.nix).
        grafanaEnvFile =
          if config.sops.templates ? "grafana.env" then config.sops.templates."grafana.env".path else null;
        # Grafana logs in via Authentik OIDC itself rather than Caddy's
        # forward_auth, so inventory.nix's monitoring node keeps auth = false.
        grafanaOidc = {
          enable = true;
          clientSecretFile = config.sops.secrets."monitoring_grafana_oauth_client_secret".path;
        };
      };

      # AI frontends: no local hardware or inference (they route to
      # litellm.internal / orin-nano), so they don't need to live on hass-pi.
      open-webui = {
        enable = true;
        ip = "10.85.50.3/24";
        hostDataDir = "/var/lib/open-webui";
        memoryLimit = "2G";
        openaiUrl = "http://${myInventory.hosts.orin-nano.ip}:9337/v1";
        oidc.enable = true;
        secretsFile =
          if (config.sops.templates ? "openwebui.env") then
            config.sops.templates."openwebui.env".path
          else
            null;
      };

      # openclaw stays on hass-pi: a fresh build fails on a pnpm-deps hash
      # mismatch in upstream's lockfile; hass-pi runs a cached build.
      #
      # Off until it has a model backend: the LiteLLM it would use is disabled.
      # Data stays in hostDataDir.
      agent-zero = {
        enable = false;
        ip = "10.85.50.5/24";
        hostDataDir = "/var/lib/agent-zero";
        memoryLimit = "1G";
      };

      # Off until it has a model backend: litellm.internal is disabled.
      # Data stays in hostDataDir.
      anythingllm = {
        enable = false;
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
        secretsFile =
          if config.sops.templates ? "hermes.env" then config.sops.templates."hermes.env".path else null;
        discord.enable = true;
      };

      # One shared worker for all personas (nix-presets persona-runtime.nix).
      # hostDataDir is deliberately not persisted: the ephemeral rootfs doesn't
      # reset a bind mount, and one persona's state must not leak into the next
      # (persona-invoke also wipes it before each start).
      persona-runtime = {
        enable = true;
        ip = "10.85.50.9/24";
        hostDataDir = "/var/lib/persona-runtime-data";
        memoryLimit = "2G";
        secretsEnvFile = "/var/lib/persona-runtime/agent.env";
        gitConfigFile = "/var/lib/persona-runtime/gitconfig";
        signingKeyFile = "/var/lib/persona-runtime/signing-key";

        # personasView joined with the per-persona sops secrets from
        # secrets.nix. `tool` must be a key in persona-runtime.nix's toolSpecs.
        # Everything is decrypted at activation, so persona-invoke only reads paths.
        personas = lib.genAttrs invocablePersonaNames (name: {
          tool = personasView.all.${name}.tool;
          signingKeyPath = config.sops.secrets."persona_${name}_signing_key".path;
          apiKeyPath =
            if config.sops.secrets ? "persona_${name}_api_key" then
              config.sops.secrets."persona_${name}_api_key".path
            else
              null;
          fullName = personasView.all.${name}."full-name";
          email = personasView.all.${name}.email;
        });
      };
    };
  };

  # anythingllm runs podman inside its ephemeral nspawn container, whose
  # ~3.9G tmpfs root is too small to unpack its image. Give podman storage
  # its own tmpfs. Gated on enable: on a disabled container it leaves
  # containers.<name> half-defined and breaks eval.
  containers = lib.mkIf config.my.containers.anythingllm.enable {
    anythingllm.tmpfs = [ "/var/lib/containers:size=8G" ];
  };

  # All services.* in one block (statix).
  services = {
    nix-gantry.host = {
      enable = true;
      subnet = "10.85.50.0/24";
      hostAddress = "10.85.50.1";
      manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
      # nix-gantry defaults this off (it needs impermanence); this fleet has it.
      enablePersistence = true;
      # persona-runtime stays embedded here rather than in container-factory
      # (its attrsOf `personas` option recurses there), so excludeFromStandalone
      # keeps the updater from looking for a manifest entry that never exists.
      # no-link: fleet preset architecture choice, not an external upstream bug.
      excludeFromStandalone = [
        "persona-runtime"
      ];
    };

    adguardhome = {
      enable = true;
      openFirewall = true;
      # The default 0.0.0.0:53 collides with resolved, NetBird DNS and
      # aardvark, so bind DNS to the LAN address only. Port 53 is opened on
      # that interface below; openFirewall covers just the web UI.
      settings = {
        http.address = "0.0.0.0:3000";
        dns.bind_hosts = [ myInventory.hosts.mac-mini.ip ];
      };
    };

    # Session GDM starts after an RDP login (see my.desktop above).
    displayManager.defaultSession = "gnome";

    gnome.gnome-remote-desktop.enable = true;

    # Alongside the dconf lock below: logind handles the power key itself
    # when no GNOME session claims it, so ignore it there too.
    logind.settings.Login.HandlePowerKey = "ignore";

    # Fleet convention (rpi5-node.nix, nasbook, orin-nano): periodic TRIM
    # alongside disko's allowDiscards, not instead of it.
    fstrim.enable = true;

    netbird.enable = true;

    # networking.nix defaults resolvconf on; with resolved off, resolv.conf
    # points at a stub nobody serves. Paired with resolvconf.enable = false below.
    resolved = {
      enable = true;
      settings.Resolve.FallbackDNS = "1.1.1.1 8.8.8.8";
      settings.Resolve.DNSSEC = "false";
    };
  };

  # grdctl --system uses the system bus, so this is a plain system service.
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
          # Runs as root on purpose: as User = "gnome-remote-desktop", grdctl's
          # internal pkexec exits 0 but silently writes no credentials.
        };
        # grdctl --system shells out to pkexec, which lives in /run/wrappers/bin,
        # not on systemd's minimal service PATH.
        environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
        script = ''
          set -euo pipefail
          umask 077
          state="/var/lib/gnome-remote-desktop/rdp-provisioning"
          mkdir -p "$state"

          if [ ! -f "$state/password" ]; then
            ${lib.getExe pkgs.openssl} rand -base64 18 > "$state/password"
            echo "Generated a new GNOME Remote Desktop (system/login-screen RDP) password for martin in $state/password"
          fi

          if [ ! -f "$state/tls.crt" ] || [ ! -f "$state/tls.key" ]; then
            ${lib.getExe pkgs.openssl} req -x509 -newkey rsa:4096 -days 3650 -nodes \
              -subj "/CN=mac-mini" \
              -keyout "$state/tls.key" -out "$state/tls.crt" 2>/dev/null
          fi

          grdctl="${lib.getExe pkgs.gnome-remote-desktop}"
          "$grdctl" --system rdp set-tls-cert "$state/tls.crt"
          "$grdctl" --system rdp set-tls-key "$state/tls.key"
          "$grdctl" --system rdp set-credentials martin "$(cat "$state/password")"
          "$grdctl" --system rdp enable
        '';
      };

      # NixOS ignores the packaged unit's [Install] WantedBy, and grdctl can't
      # create the symlink at runtime (read-only /etc), so declare it here.
      gnome-remote-desktop = {
        after = [ "gnome-remote-desktop-system-rdp-setup.service" ];
        requires = [ "gnome-remote-desktop-system-rdp-setup.service" ];
        wantedBy = [ "graphical.target" ];
      };

      # Clear AFTERG3_EN (bit 0 of Cougar Point LPC GEN_PMCON_3 at 00:1f.0+0xa4)
      # so the Mac Mini powers back on automatically when AC returns.
      mac-mini-auto-power-on = {
        description = "Enable automatic power-on after AC power loss (Macmini5,x LPC GEN_PMCON_3)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          setpci="${lib.getExe' pkgs.pciutils "setpci"}"
          cur="$("$setpci" -s 00:1f.0 0xa4.b)"
          next=$(printf '%02x' $(( 0x$cur & ~1 )))
          if [ "$cur" != "$next" ]; then
            "$setpci" -s 00:1f.0 0xa4.b="$next"
          fi
        '';
      };
    };
  };

  # Never suspend: no input device ever wakes it, and resume is broken on this
  # hardware. The power button counts too: with no display, "interactive"
  # falls through to suspend. Locked, because the user db would otherwise
  # shadow a plain system default.
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

  # The GDM greeter stays alive with its own gsd-power under the "gdm"
  # profile, which the user lock above doesn't cover. This list merges
  # with desktop.nix's gdm database.
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

  # The headless unit uses the portal API, which refuses locked sessions
  # (gnome-remote-desktop #16), and it also runs in the greeter's
  # gnome-session. Its Conflicts= stops the system daemon and takes port 3389.
  systemd.user.services.gnome-remote-desktop-headless.enable = false;

  # All environment.* in one block (statix).
  environment = {
    persistence."/nix/persist" = {
      # /home has no disk-backed mount of its own (disko.nix only declares
      # /nix and /nix/persist) — it lives under the tmpfs "/" declared near
      # the bottom of this file, so it's wiped every reboot by default.
      users.martin.directories = [
        ".config" # GNOME/dconf settings, GTK, mimeapps.list, google-chrome
      ];

      directories = [
        # System RDP credentials and TLS cert; otherwise they regenerate every boot.
        "/var/lib/gnome-remote-desktop"

        # my.containers hostDataDirs are persisted by services.nix-gantry.host
        # automatically; listing them again trips impermanence's duplicate check.

        # Homarr was removed (home.kleinbem.dev is the dashboard); its old data
        # stays until it's deliberately deleted.
        "/var/lib/homarr"

        # AdGuard is a DynamicUser service, so persist /var/lib/private, not
        # the /var/lib symlink.
        "/var/lib/private/AdGuardHome"
      ]
      # DynamicUser too; holds the last-pushed IP so restarts skip the API call.
      ++ lib.optional config.services.cloudflare-dyndns.enable "/var/lib/private/cloudflare-dyndns";
    };

    systemPackages = with pkgs; [
      sops
      age
      libfido2
      # Browser (google-chrome) is declared in the home-manager block above,
      # not here — installed plain, not firejailed (see the Chrome note in
      # modules/nixos/firejail.nix).
    ];
  };

  # Initrd SSH fallback for when Tang is unreachable: with no console, the
  # passphrase can only be typed remotely.
  boot = {
    initrd = {
      # Onboard NIC; without it neither Tang nor initrd SSH has a network.
      kernelModules = [ "tg3" ];

      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_mac-mini" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_mac-mini" = lib.mkForce config.my.hostSecrets.initrdSshKey;
    };

    loader.systemd-boot = {
      enable = true;
      # Same cap orin-nano uses — an unpruned ESP fills up with stale
      # per-generation kernels/initrds over time.
      configurationLimit = 10;
    };
  };

  # Microcode, plus firmware for the Broadcom Wi-Fi/Bluetooth. The tg3
  # Ethernet needs no blob, so Tang unlock doesn't depend on this.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;

    # VAAPI for Zoom recording. i965 (intel-vaapi-driver), since iHD needs
    # Gen8+ and this is Sandy Bridge; encode on Gen6 is flaky, decode is fine.
    graphics = {
      enable = true;
      extraPackages = with pkgs; [ intel-vaapi-driver ];
    };
  };

  # Boot ROM is at 133.0.0.0.0, the last Apple shipped for Macmini5,x and not
  # on LVFS, so stale firmware isn't a suspect for boot trouble.

  networking = {
    hostName = "mac-mini";

    # Paired with services.resolved above.
    resolvconf.enable = lib.mkForce false;

    # nftables backend so extraForwardRules works (see nixos-nvme's network.nix).
    nftables = {
      enable = true;
      # Inbound SMTP fallback: forwards any WAN:25 still hitting mac-mini
      # to Stalwart on nasbook.
      tables.mail-nat = {
        family = "inet";
        content = ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            iifname "enp2s0f0" tcp dport 25 dnat ip to ${myInventory.network.nodes.stalwart.ip}
          }
        '';
      };
    };

    # Alertmanager has no auth of its own, so only Caddy (behind Authentik
    # forward_auth) may reach its port. core-pi masquerades all cbr0 egress,
    # so Caddy arrives as core-pi's LAN IP, not its container IP.
    # 10.85.50.1 is this host's bridge, for local admin.
    firewall = {
      enable = true;
      backend = "nftables";
      filterForward = true;
      extraForwardRules = lib.mkBefore ''
        ip daddr ${myInventory.network.nodes.alertmanager.ip} tcp dport ${toString myInventory.network.nodes.alertmanager.port} ip saddr { ${myInventory.hosts.core-pi.ip}, 10.85.50.1 } accept
        ip daddr ${myInventory.network.nodes.alertmanager.ip} tcp dport ${toString myInventory.network.nodes.alertmanager.port} drop
      '';
      # AdGuard Home DNS (services.adguardhome, bound to the LAN address).
      interfaces."enp2s0f0" = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };
    };

    interfaces."enp2s0f0" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.0.16";
          prefixLength = 16;
        }
      ];
      # No physical access once mounted, so power-on is remote.
      wakeOnLan.enable = true;
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "enp2s0f0";
    };
  };

  # Keeps mail.kleinbem.dev's A record on the dynamic WAN IP. Not in Terraform:
  # a value that changes by itself would fight every apply. The rest of the
  # mail DNS stays in nix/infra. Gated on the token so a missing one can't
  # break activation (see secrets.nix).
  services.cloudflare-dyndns = lib.mkIf (config.sops.secrets ? "cloudflare_dyndns_token") {
    enable = true;
    apiTokenFile = config.sops.secrets."cloudflare_dyndns_token".path;
    domains = [ "mail.kleinbem.dev" ];
    ipv4 = true;
    ipv6 = false;
    proxied = false; # SMTP can't be Cloudflare-proxied
  };

  # lz4 instead of the fleet's zstd: cheaper CPU per page on this 2-core CPU.
  zramSwap.algorithm = lib.mkForce "lz4";

  # Stateless root: disko.nix declares only disk-backed mounts, so the tmpfs
  # "/" and "/var" live here.
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
