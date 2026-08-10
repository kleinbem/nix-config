# Migrate Secrets (Rclone) to Separate Repo

## Goal Description

Move sensitive configurations to a dedicated, private `nix-secrets` repository. This separation allows the main `nix-config` to be public while keeping secrets private and encrypted.

> [!NOTE]
> We will create the `nix-secrets` repo locally first. You should create a private GitHub repository and push it later.

## User Review Required
>
> [!WARNING]
> **Read-Only Trade-off (Reiteration)**: Rclone config will be read-only. Updates to tokens require manually updating the secret in the `nix-secrets` repo.

## Proposed Changes

### Infrastructure

#### [NEW] [../nix-secrets/](file:///home/martin/Develop/github.com/kleinbem/nix-secrets)

- New git repository.
- Contains `.sops.yaml` (moved from main repo).
- Contains `secrets.yaml` (the actual encrypted secrets).

### Main Configuration (nix-config)

#### [MODIFY] [flake.nix](file:///home/martin/Develop/github.com/kleinbem/nix-config/flake.nix)

- Add `inputs.nix-secrets` pointing to the local path (initially).

  ```nix
  nix-secrets = {
    url = "git+file:///home/martin/Develop/github.com/kleinbem/nix-secrets";
    flake = false;
  };
  ```

#### [NEW] [modules/home-manager/secrets.nix](file:///home/martin/Develop/github.com/kleinbem/nix-config/modules/home-manager/secrets.nix)

- Enable `sops`.
- Point `sops.defaultSopsFile` to `${inputs.nix-secrets}/secrets.yaml`.
- Define `sops.secrets.rclone_config`.

#### [DELETE] [.sops.yaml](file:///home/martin/Develop/github.com/kleinbem/nix-config/.sops.yaml)

- Move this file to the new repo.

## Verification Plan

1. **Setup Repo**: I will create the directory and move configs.
2. **Create Secret**: You run `sops` in the new repo.
3. **Deploy**: `just deploy`.
4. **Verify**: Check `~/.config/rclone/rclone.conf` symlink.
