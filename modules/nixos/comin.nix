# Pull-based fleet deploy via comin (github:nlewo/comin). The host polls the
# `production` branch of kleinbem/nix-config and switches to it: 60 s polling,
# signed-head verification, a per-host testing branch, Prometheus metrics and
# generation retention come from upstream instead of our own timer + ntfy
# listener + cache probe (my.deploy.autoUpgrade). Hosts opt in per host; the
# two mechanisms are mutually exclusive.
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

        # Scoped to comin's own nix client (root is a trusted user, so the
        # daemon honours it) instead of the host-wide nix.settings.max-jobs.
        systemd.services.comin.environment.NIX_CONFIG = lib.mkIf cfg.requireCache "max-jobs = 0";

        networking.firewall.interfaces.wt0.allowedTCPPorts = lib.mkIf cfg.exporter.enable [
          cfg.exporter.port
        ];

        # Same structured journald event autoUpgrade emits, so the Loki
        # "current generation per host" query keeps working across both.
        system.activationScripts.deployLog = lib.stringAfter [ "users" ] ''
          ${pkgs.systemd}/bin/systemd-cat -t nix-config-deploy -p info <<EOF
          event=switch host=${cfg.hostName} system=$(readlink -f /run/current-system) flake=${cfg.url}#${cfg.branch}
          EOF
        '';
      }

      # comin's state (last deployed commit, deployment history behind the
      # boot entries it manages) must outlive the tmpfs root.
      (lib.optionalAttrs (options.environment ? persistence) {
        environment.persistence."/nix/persist".directories = [ "/var/lib/comin" ];
      })
    ]
  );
}
