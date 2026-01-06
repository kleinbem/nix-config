# GitHub Hardware Security Setup

## 1. Apply System Configuration

Your machine is configured to use the hardware key for signing, but you need to apply the changes to the system:

```bash
sudo nixos-rebuild switch --flake .
```

(Or `just switch` if permissions allow).

## 2. Configure GitHub

You need to tell GitHub about your new "Resident" YubiKey SSH key.

1. Go to **[GitHub Settings -> SSH and GPG Keys](https://github.com/settings/keys)**.
2. Click **New SSH Key**.
3. **Title:** `NixOS NVMe (YubiKey Primary)`
4. **Key Type:** Select **Authentication Key**.
5. **Key:** Paste the following:

    ```text
    sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHv/QOJAllPiFXUrLhpexjLKD8xDEu878ROd21+XlCsdAAAABHNzaDo= yubikey-primary-github
    ```

6. Click **Add SSH Key**.

**Crucial Step for "Verified" Commits:**
7.  Click **New SSH Key** (Again).
8.  **Title:** `NixOS NVMe (Signing)`
9.  **Key Type:** Select **Signing Key**.
10. **Key:** Paste the **SAME** key again set above.
11. Click **Add SSH Key**.

## 3. Verify

After adding the keys:

1. Make a commit in this repo: `git commit --allow-empty -m "Testing hardware signing"`
    * *It should ask for your YubiKey PIN/Touch.*
2. Push: `git push`
    * *It should verify authentication with your YubiKey.*
3. Check the commit on GitHub. It should have a green **[Verified]** badge.

## 4. Setup Backup YubiKey (Recommended)

You should generate a key for your backup device so you can access GitHub if you lose your primary.

1. **Insert Backup YubiKey.**
2. Run this command (it saves to a different file to avoid overwriting your primary):

    ```bash
    ssh-keygen -t ed25519-sk -O resident -O verify-required -C "yubikey-backup-github" -f ~/.ssh/id_ed25519_sk_backup
    ```

    *(If asked for a passphrase, you can stick to the same policy as your primary: empty/none, relying on the hardware PIN).*

3. **Add to GitHub:**
    * Go to **[GitHub Settings](https://github.com/settings/keys)**.
    * Click **New SSH Key**.
    * **Title:** `NixOS NVMe (YubiKey Backup)`
    * **Key Type:** Select **Authentication Key**.
    * **Key:** Paste the content of `~/.ssh/id_ed25519_sk_backup.pub`.

    *> **Note:** Do NOT add this as a Signing Key yet. GitHub usually expects one active signing key. If you lose your primary key, you will then add this backup key as a Signing Key and update your `shell.nix` configuration.*

## 5. Backup Strategy

For maximum safety, you should back up the "software parts" of your setup. You have two good options:

1. **Bitwarden (Secure Note):** Simple and secure.
2. **Private Git Repo (`nix-secrets`):** Best for automation if you use Nix/Home Manager to manage secrets later.

### What to Backup

1. **Public Keys:** `~/.ssh/id_ed25519_sk.pub` and `~/.ssh/id_ed25519_sk_backup.pub`.
2. **Key Handles:** `~/.ssh/id_ed25519_sk` and `~/.ssh/id_ed25519_sk_backup`.
    * *Note: These are safe to back up. They are "handles" that tell SSH how to find the secret on your YubiKey.*
3. **U2F Enrollment:** `~/.config/Yubico/u2f_keys`.
    * *Recommended Bitwarden Note Name:* `NixOS U2F Config (u2f_keys)`
    * *Note: This file is technically public info (key handles), so it is safe to put in a private `nix-secrets` repo.*

### What Cannot Be Backed Up

* **The Private Keys:** These live inside the hardware and cannot be extracted. Your physical backup is your **Backup YubiKey**.
