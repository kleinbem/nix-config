# Declarative Migration Walkthrough (Nixvim, VS Code, SSH)

We migrated from "Imperative" (manual changes) to "Declarative" (Nix-managed) configuration for better stability and reproducibility.

## 1. What Changed?

### Neovim -> Nixvim

* **Old:** Manual `git clone` of LazyVim.
* **New:** `programs.nixvim` module.
* **Effect:** Plugins, themes (Tokyonight), and settings (LSP, Treesitter) are now built into your system closure. You can confirm this by running `nvim` — it should look configured without any `~/.config/nvim` files.

### VS Code

* **Old:** Manual extension installation.
* **New:** `programs.vscode` with `profiles.default`.
* **Effect:** Extensions like `gitlens`, `github-copilot`, and `nix-ide` are installed automatically. User settings are enforced by Nix.

### SSH Config

* **Old:** Manual `~/.ssh/config` editing.
* **New:** `programs.ssh` in `shell.nix`.
* **Effect:** The GitHub host alias and YubiKey "resident key" loading (`addKeysToAgent`) are now standard.

## 2. Secrets Management (SOPS + nix-secrets)

We moved sensitive files (like `rclone.conf`) to a separate private repository.

### Structure

* **Main Repo:** `~/Develop/github.com/kleinbem/nix-config` (Public)
* **Secrets Repo:** `~/Develop/github.com/kleinbem/nix-secrets` (Private)

### Workflow: Adding a New Secret

1. Go to secrets repo: `cd ../nix-secrets`
2. Edit encrypted file: `sops secrets.yaml`
3. Commit changes: `git commit -am "Update secrets"`
4. Deploy system: `cd ../nix-config && just deploy`

## 3. Verification Steps

1. **Check SSH:**

    ```bash
    ssh -T git@github.com
    ```

    (Should authenticate using your YubiKey automatically).

2. **Check Neovim:**

    ```bash
    nvim
    ```

    (Should load with Tokyonight theme and no errors).

3. **Check VS Code:**
    Open VS Code. Check extensions. You should see "This extension is managed by Nix" (or simply installed).

4. **Check Rclone:**

    ```bash
    rclone listremotes
    ```

    Should show `gdrive:` and `onedrive:`.

## 4. Cleanup

After verifying everything works, you can archive your old imperative configs:

```bash
# If you haven't already:
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.config/Code/User/settings.json ~/.config/Code/User/settings.json.bak
rm ~/.config/rclone/rclone.conf # MUST remove for Nix to take over
# ~/.ssh/config should be empty or managed
```
