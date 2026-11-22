# Pull-based deploy via comin (github:nlewo/comin): the host polls the
# `production` branch of kleinbem/nix-config and switches to signed heads.
# Per-host opt-in, mutually exclusive with my.deploy.autoUpgrade.
{
  config,
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
let
  cfg = config.my.deploy.comin;
  keys = import ./keys.nix;

  # keys.nix carries comments after the key material; comin's allowed-signers
  # parser accepts only "principal [namespaces=...] type base64".
  bareKey = k: lib.concatStringsSep " " (lib.take 2 (lib.splitString " " k));
  allowedSigners = pkgs.writeText "comin-allowed-signers" (
    lib.concatMapStrings (k: ''martin.kleinberger@gmail.com namespaces="git" ${bareKey k}'' + "\n") (
      with keys.ssh;
      [
        fido2-notouch
        fido2
        fido2-backup
      ]
    )
  );

  # localAssembly: comin waits for confirmation after each evaluation and
  # keeps max-jobs = 0. comin-assemble checks the evaluated drv: when no
  # package is missing from the cache (scripts/heavy-drvs.sh) it builds the
  # assembly steps and confirms, and comin's build then finds everything.
  heavyDrvs = pkgs.callPackage ../../scripts/heavy-drvs.nix { nix = config.nix.package; };
  stateDir = "/run/comin-assemble";
  alertAfterSec = 3 * 3600;
  hasAlertTopic = config.sops.secrets ? ntfy_alert_topic;

  assemble = pkgs.writeShellApplication {
    name = "comin-assemble";
    runtimeInputs = [
      config.nix.package
      config.services.comin.package
      pkgs.coreutils
      pkgs.curl
      pkgs.gnused
      pkgs.jq
      heavyDrvs
    ];
    text = ''
      st=$(comin status --json)
      uuid=$(jq -r '.build_confirmer.submitted' <<<"$st")
      [ -n "$uuid" ] || exit 0
      sha=$(jq -r '.builder.generation.source.git.selected_commit_id' <<<"$st")

      # One alert when a generation waits too long, whatever holds it.
      mkdir -p ${stateDir}
      [ -e "${stateDir}/$uuid" ] || touch "${stateDir}/$uuid"
      waited=$(($(date +%s) - $(stat -c %Y "${stateDir}/$uuid")))
      if [ "$waited" -ge ${toString alertAfterSec} ] && [ ! -e "${stateDir}/$uuid.alerted" ]; then
        touch "${stateDir}/$uuid.alerted"
        ${lib.optionalString hasAlertTopic ''
          topic=$(cat ${config.sops.secrets.ntfy_alert_topic.path} 2>/dev/null || true)
          auth=()
          if [ -r /run/secrets/ntfy_alert_token ]; then
            auth=(-H "Authorization: Bearer $(cat /run/secrets/ntfy_alert_token)")
          fi
          [ -z "$topic" ] || curl -fsS --max-time 15 "''${auth[@]}" \
            -H "Title: ${cfg.hostName}: deploy stuck" -H "Tags: warning" \
            -d "comin has waited $((waited / 3600)) h to build $sha; see journalctl -u comin-assemble." \
            "https://ntfy.kleinbem.dev/$topic" >/dev/null || true
        ''}
      fi

      if [ "$(jq -r '.builder.generation.uuid' <<<"$st")" != "$uuid" ] ||
        [ "$(jq -r '.builder.generation.eval_status' <<<"$st")" != evaluated ]; then
        exit 0
      fi
      drv=$(jq -r '.builder.generation.drv_path' <<<"$st")
      # Negative TTL 0: see a package as soon as CI pushes it.
      if ! out=$(nix build --no-link --dry-run --option always-allow-substitutes true \
        --option narinfo-cache-negative-ttl 0 "$drv^*" 2>&1); then
        echo "$out"
        echo "comin-assemble: dry-run of $drv ($sha) failed"
        exit 1
      fi
      classified=$(heavy-drvs <<<"$out")
      heavy=$(sed -n 's/^heavy //p' <<<"$classified")
      if [ -n "$heavy" ]; then
        echo "comin-assemble: $sha waits for $(wc -l <<<"$heavy") packages from CI, e.g. $(head -1 <<<"$heavy")"
        exit 0
      fi
      mapfile -t small < <(sed -n 's/^small //p' <<<"$classified")
      if [ "''${#small[@]}" -gt 0 ]; then
        echo "comin-assemble: building ''${#small[@]} assembly steps for $sha"
        nix build --no-link -L --option always-allow-substitutes true "''${small[@]/%/^*}"
      fi
      # accept takes no id: confirm only if the generation checked here still
      # waits. A newer one slipping in would still fail on max-jobs = 0.
      [ "$(comin status --json | jq -r '.build_confirmer.submitted')" = "$uuid" ] || exit 0
      comin confirmation accept
      rm -f "${stateDir}/$uuid" "${stateDir}/$uuid.alerted"
    '';
  };
in
{
  imports = [ inputs.comin.nixosModules.comin ];

  options.my.deploy.comin = {
    enable = lib.mkEnableOption ''
      pull-based deploy via comin: poll a branch of kleinbem/nix-config and
      switch to every new head. Replaces my.deploy.autoUpgrade on the host
    '';

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/kleinbem/nix-config.git";
      description = "Git remote comin polls. Public repo, no auth needed.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "production";
      description = ''
        Branch to deploy. promote-production advances it to the main SHA that
        passed build-all and the cache gate. comin refuses a head that is not
        a descendant of what it last deployed, so this branch only ever moves
        forward.
      '';
    };

    testingBranch = lib.mkOption {
      type = lib.types.str;
      default = "testing-${config.networking.hostName}";
      description = ''
        Per-host canary branch. A head on top of `branch` is applied with
        switch-to-configuration test (no boot entry) on this host only. Push
        one to try a change without SSH; delete it to fall back.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "nixosConfigurations attribute comin evaluates.";
    };

    pollPeriod = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Seconds between git fetches.";
    };

    verifySignatures = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Deploy only heads signed by GitHub's merge key (squash merges and the
        docs-sync bot, pki/github-web-flow.asc) or by Martin's SSH signing
        keys from keys.nix. A tampered remote cannot push a config.
      '';
    };

    requireCache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Never compile on-device: comin's nix client runs with max-jobs = 0,
        so a closure the cache lacks fails fast instead of rebuilding a
        kernel on a Pi (same guard my.deploy.autoUpgrade.requireCache uses).
        comin retries every 30 s, so a cache blip costs nothing. Leave false
        on hosts that build locally (nixos-nvme, orin-nano).
      '';
    };

    localAssembly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        With `requireCache`, build the system-assembly steps (etc, units,
        the toplevel) on the host, so CI only has to cache the packages.
        comin waits for confirmation (buildConfirmer manual) and keeps
        max-jobs = 0; comin-assemble confirms once no package is missing
        from the cache (scripts/heavy-drvs.sh) and the assembly steps are
        built. A generation waiting over 3 h sends one ntfy alert.
      '';
    };

    buildTimeout = lib.mkOption {
      type = lib.types.int;
      default = 1800;
      description = "Seconds before comin cancels a build (substitute-only pulls take under a minute).";
    };

    exporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Serve comin's Prometheus metrics on the NetBird interface.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 4243;
        description = "Exporter port, opened on wt0 only.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.localAssembly -> cfg.requireCache;
            message = "my.deploy.comin.localAssembly only applies with requireCache.";
          }
          {
            assertion = !config.my.deploy.autoUpgrade.enable;
            message = "my.deploy.comin and my.deploy.autoUpgrade would both switch this host; enable one.";
          }
        ];

        services.comin = {
          enable = true;
          hostname = cfg.hostName;
          inherit (cfg) buildTimeout;
          remotes = [
            {
              name = "origin";
              inherit (cfg) url;
              poller.period = cfg.pollPeriod;
              branches = {
                main.name = cfg.branch;
                testing.name = cfg.testingBranch;
              };
            }
          ];
          gpgPublicKeyPaths = lib.mkIf cfg.verifySignatures [ "${../../pki/github-web-flow.asc}" ];
          sshAllowedSignersPath = lib.mkIf cfg.verifySignatures "${allowedSigners}";
          exporter.port = cfg.exporter.port;
        };

        # Scoped to comin's nix client, not host-wide. always-allow-substitutes:
        # nixpkgs marks system-path, etc and writeText* `allowSubstitutes = false`,
        # which max-jobs = 0 can't build locally, so every upgrade would fail.
        systemd.services.comin.environment.NIX_CONFIG = lib.mkIf cfg.requireCache ''
          max-jobs = 0
          always-allow-substitutes = true
        '';

        networking.firewall.interfaces.wt0.allowedTCPPorts = lib.mkIf cfg.exporter.enable [
          cfg.exporter.port
        ];

        # Same structured journald event autoUpgrade emits, so the Loki
        # "current generation per host" query keeps working across both.
        system.activationScripts.deployLog = lib.stringAfter [ "users" ] ''
          ${pkgs.systemd}/bin/systemd-cat -t nix-config-deploy -p info <<EOF
          event=switch host=${cfg.hostName} system=$(readlink -f "$systemConfig") flake=${cfg.url}#${cfg.branch}
          EOF
        '';
      }

      (lib.mkIf cfg.localAssembly {
        services.comin.buildConfirmer.mode = "manual";
        systemd.services.comin-assemble = {
          description = "Assemble and confirm the generation comin waits on";
          after = [ "comin.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe assemble;
            TimeoutStartSec = cfg.buildTimeout;
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        systemd.timers.comin-assemble = {
          wantedBy = [ "timers.target" ];
          # Calendar, not OnBootSec + OnUnitInactiveSec: with a run that ends
          # in under a second that pair re-fired at once and hit the start limit.
          timerConfig.OnCalendar = "*:0/2";
        };
      })

      # comin's state (last deployed commit, deployment history behind the
      # boot entries it manages) must outlive the tmpfs root.
      (lib.optionalAttrs (options.environment ? persistence) {
        environment.persistence."/nix/persist".directories = [ "/var/lib/comin" ];
      })
    ]
  );
}
