# Deployment

Hosts deploy themselves from the `production` branch. Nothing pushes over SSH in normal operation.

## Pipeline

1. A change lands on `main` through a PR (signed commits, required checks, auto-merge).
2. **Build & Cache All** (`build-all.yaml`) builds every host toplevel and container closure and pushes them to Attic. nixos-nvme has its own `build-nvme.yaml`.
3. **Promote → production** (`promote-production.yaml`) checks that each pull-deploy host's closure can be fetched from the caches the device trusts, then moves the `production` tag and branch to that SHA and publishes the container manifest.
4. Hosts pick it up:
   - **comin** (`my.deploy.comin`, `modules/nixos/comin.nix`; core-pi, hass-pi, mac-mini, nasbook, orin-nano): polls `production` every 60 s, accepts only heads signed by GitHub's merge key (`pki/github-web-flow.asc`) or Martin's SSH keys, and runs `switch-to-configuration switch`. `production` only moves forward: comin refuses a head that isn't a descendant of what it last deployed. With `requireCache`, its nix client runs with `max-jobs = 0`, so a cache miss fails in seconds instead of building. State in `/var/lib/comin`, metrics on port 4243 over NetBird, `comin status` on the host shows what is deployed.
   - **autoUpgrade** (`my.deploy.autoUpgrade`, `modules/nixos/auto-upgrade.nix`; nixos-nvme only): nightly `nixos-rebuild switch` against the `production` tag plus an ntfy fast path. By hand: `just dev::apply`.
   - **container updater**: nightly pull of the container manifest.

## Before merging

```bash
just dev::preflight     # formatting, pre-commit-check, nixos-nvme eval
just dev::check-hosts   # nix flake check over every host
just dev::impact <file> # which hosts a change to that file touches
```

## Canary one host

On comin hosts, push a `testing-<host>` branch on top of `production`; its head must be signed with Martin's SSH key or by GitHub (jj signs by default), or comin rejects it. comin on that host applies it with `switch-to-configuration test` (no boot entry). Delete the branch to fall back.

## Rollback

- **Bad commit:** revert it in a PR. It merges, builds, promotes, and every host picks it up.

  ```bash
  jj revert -r <bad> -o @
  ```

- **One host broken right now:** `sudo nixos-rebuild switch --rollback` on the host, or pick the previous generation in the boot menu. This is local only; comin deploys the next `production` head as usual, so land the revert too.

## Emergency path

`just deployment::deploy <host>` deploys with colmena over SSH, for a host whose agent can't reach the repo or the cache. On core-pi and hass-pi it refuses to run when the host booted from the SD card.

USB recipes for offline disks: `just deployment::pi-update-usb <host>`, `nasbook-update-usb`, `mac-mini-update-usb`, `orin-update-usb`.

## Router

core-gateway and the APs run OpenWrt and deploy through openwrt-config (Ansible), not this pipeline.

## Secrets changes

Edit with `sops` in kleinbem-secrets and land the change like any other. Never copy a decrypted key or secret to disk; the master keys are the two YubiKeys. See [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md).
