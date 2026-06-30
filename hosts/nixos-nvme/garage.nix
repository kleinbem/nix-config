# Garage S3 object storage — INTERIM single-node on nixos-nvme.
#
# DRAFT / NOT YET WIRED IN: this file is not imported by the host yet. To
# activate: (1) add the two sops secrets below, (2) import this from
# hosts/nixos-nvme/default.nix, (3) `just apply`, (4) run the one-time init at
# the bottom. Without the secrets the build will fail (sops template), so don't
# import until they exist.
#
# Data lives on /mnt/data (1.4 TB free, btrfs = CoW+snapshots → mitigates the
# Garage LMDB single-node crash-fragility caveat). replication_factor = 1 because
# it's a single node for now; when nasbook comes online, add it as a second node
# and `garage layout` rebalance, then drain this one. R2 offsite remains the
# durability backstop regardless.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # --- Secrets (add to nix-secrets/secrets.yaml, then `sops updatekeys`) -------
  #   garage_rpc_secret   : `openssl rand -hex 32`  (32-byte hex, REQUIRED format)
  #   garage_admin_token  : `openssl rand -base64 32` (any opaque string)
  sops = {
    secrets.garage_rpc_secret = { };
    secrets.garage_admin_token = { };

    # Rendered env file injected into the service (keeps secrets OUT of the
    # world-readable /etc/garage.toml in the Nix store). Garage reads these env vars.
    templates."garage.env".content = ''
      GARAGE_RPC_SECRET=${config.sops.placeholder.garage_rpc_secret}
      GARAGE_ADMIN_TOKEN=${config.sops.placeholder.garage_admin_token}
    '';
  };

  # --- Storage dirs on /mnt/data, owned by a static garage user ---------------
  # (Static user instead of the module's default DynamicUser, so a fixed
  # external data dir has stable ownership.)
  users.users.garage = {
    isSystemUser = true;
    group = "garage";
  };
  users.groups.garage = { };

  # Pre-create the data/metadata dirs in a SEPARATE, un-sandboxed oneshot ordered
  # before garage. garage's own unit has ReadWritePaths=/mnt/data/garage/{meta,data}
  # (set by the module for non-default dirs), and systemd requires those to exist
  # when it sets up the unit's mount namespace. Neither tmpfiles (races a live
  # `switch`) nor an ExecStartPre with `+` reliably creates them first — the `+`
  # still inherited garage's mount namespace here (status 226/NAMESPACE). A plain
  # oneshot has no namespace directives, so its mkdir runs in the host namespace.
  systemd.services.garage-init-dirs = {
    description = "Pre-create Garage data/metadata directories";
    before = [ "garage.service" ];
    requiredBy = [ "garage.service" ];
    unitConfig.RequiresMountsFor = "/mnt/data";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.coreutils}/bin/mkdir -p /mnt/data/garage/meta /mnt/data/garage/data"
        "${pkgs.coreutils}/bin/chown -R garage:garage /mnt/data/garage"
      ];
    };
  };

  # Run garage as the static garage user (the module defaults to DynamicUser = a
  # random UID, which can't write the garage-owned dirs); wait for the mount.
  systemd.services.garage = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "garage";
      Group = "garage";
    };
    unitConfig.RequiresMountsFor = "/mnt/data";
  };

  # --- The service ------------------------------------------------------------
  services.garage = {
    enable = true;
    package = pkgs.garage_2; # v2.3.0 (pkgs.garage_1 is the old 1.3.x line)
    environmentFile = config.sops.templates."garage.env".path;

    settings = {
      metadata_dir = "/mnt/data/garage/meta";
      data_dir = "/mnt/data/garage/data";

      # lmdb is the default + most-tested engine. The 2026-04 roadmap flags lmdb
      # crash-fragility (replacement planned); btrfs CoW under the data dir +
      # the R2 offsite copy are the mitigations. Switch to "sqlite" here if you
      # want to prioritise crash-resilience over raw speed on this single node.
      db_engine = "sqlite";

      replication_factor = 1; # single node (interim). Raise + add nodes later.

      # rpc + admin stay on loopback (single node — nothing else needs them).
      # For multi-node later, rpc must be reachable by the other node (bind the
      # LAN/NetBird interface + open 3901 then).
      rpc_bind_addr = "127.0.0.1:3901";
      rpc_public_addr = "127.0.0.1:3901";

      s3_api = {
        s3_region = "garage";
        # Bind all interfaces so the Caddy CONTAINER can reach this host-native
        # service via the cbr0 bridge IP (10.85.46.1:3900); the host firewall
        # keeps the LAN out, and S3 SigV4 access keys protect it regardless.
        # The `garage` node entry in inventory.nix points Caddy here.
        api_bind_addr = "[::]:3900";
        root_domain = ".s3.kleinbem.dev"; # vhost-style bucket addressing
      };

      admin.api_bind_addr = "127.0.0.1:3903"; # token via GARAGE_ADMIN_TOKEN env
    };
  };

  # Optional community web UI for the gap left by Garage's not-yet-shipped admin
  # GUI. Uncomment to expose it (also front via Caddy; it talks to the admin API).
  # environment.systemPackages = [ pkgs.garage-webui ];
}
# --- ONE-TIME INIT after first `just apply` (imperative; run on the host) -----
# The `garage` CLI wrapper auto-sources the env file (RPC secret + admin token).
#
#   # 1. give this node storage capacity and apply the layout:
#   garage layout assign -z dc1 -c 1T "$(garage node id -q | cut -d@ -f1)"
#   garage layout apply --version 1
#
#   # 2. create buckets + scoped keys (first consumers):
#   garage bucket create backups
#   garage bucket create tofu-state
#   garage key create restic-key
#   garage key create tofu-key
#   garage bucket allow --read --write backups     --key restic-key
#   garage bucket allow --read --write tofu-state  --key tofu-key
#   # → note each key's Key ID + Secret (shown once) for restic / the tofu pg-or-s3 config
#
# Next wiring (separate step): a network.nodes entry + Caddy upstream so the S3
# API is reachable at https://s3.kleinbem.dev (LAN + over NetBird for CI).
