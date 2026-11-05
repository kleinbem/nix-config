# Home Manager

User environments are Home Manager modules, built as part of the NixOS system. A switch (`just apply` or comin) activates them through `home-manager-<user>.service`; there is no separate `home-manager switch`.

## Layout

| Path | What |
|---|---|
| `users/<user>/home.nix` | The user's HM config (martin, dhirujaan). `home-phone.nix` / `home-tablet.nix` are the nix-on-droid variants. |
| `users/<user>/nixos.nix` | System side: the account, groups, password hash. |
| `modules/home-manager/default.nix` | Shared bundle every user imports: dev, ai-agents, security, pentesting, vscode, nixvim, secrets, syncthing, service-launchers, android, plus HM modules from nix-presets and cadre. |
| `modules/home-manager/gnome.nix` | GNOME settings, imported separately by users on a GNOME host. |

Hosts attach users in their own file, e.g. `hosts/nixos-nvme/default.nix`:

```nix
home-manager.users.${config.my.username} = {
  imports = [ "${self}/users/martin/home.nix" ];
};
```

`modules/nixos/base.nix` sets `useGlobalPkgs`, `useUserPackages` and `backupFileExtension = "backup"`, and passes `inputs`, `myInventory`, `secretFile` and `my` (the host's `config.my`) to every HM module. `osConfig` (the full NixOS config) comes from Home Manager itself.

## Options

Only these modules in `modules/home-manager/` have an enable switch:

| Option | What |
|---|---|
| `modules.gnome.enable` | GNOME settings and extensions |
| `modules.ai-agents.enable` | Claude Code, goose and other agents |
| `modules.android.enable` | Android tools (apkeep, phone/tablet CLIs) |
| `modules.service-launchers.enable` | Desktop launchers for homelab services |
| `modules.syncthing.enable` | Syncthing, with `vaultPath` for the Obsidian vault |

dev, security, pentesting, vscode, nixvim and secrets are always on once imported. Heavier pentest tools live in the nix-devshells pentest shell (`just devshell::pentest` from `nix/`). Modules from other flakes (`modules.opencode`, `modules.herdr`, `modules.mcp`, `modules.devshell-launchers`) are documented there.

To enable something only on GNOME hosts:

```nix
{ osConfig, lib, ... }:
{
  modules.gnome.enable = lib.mkDefault osConfig.my.desktop.gnome.enable;
}
```

## Adding a user

1. `users/<user>/nixos.nix` with `users.users.<user>`; put the password hash in kleinbem-secrets (see `users/dhirujaan/nixos.nix`).
2. `users/<user>/home.nix`, taking the args it uses:

   ```nix
   { pkgs, ... }:
   {
     imports = [ ../../modules/home-manager/default.nix ];
     home.packages = [ pkgs.ripgrep ];
     home.stateVersion = "25.11";
   }
   ```

3. Import both from the host and set `home-manager.users.<user>`.

`home.stateVersion` stays at the release the user was created on. Change it only when the HM release notes say so.

## Secrets

Secrets a user needs come from sops-nix on the NixOS side; point the program at the decrypted path instead of copying it into `$HOME`:

```nix
sops.secrets.my_token = {
  owner = config.my.username;
  sopsFile = secretFile "nix/per-host/<host>.yaml";
};
# then hand config.sops.secrets.my_token.path to the program or unit
```

For environment variables a service needs, render a `sops.templates` file and load it with `EnvironmentFile`; don't `$(cat …)` secrets into `home.sessionVariables`.

## Useful commands

```bash
systemctl status home-manager-martin          # did activation succeed?
journalctl -u home-manager-martin -n 50
```

Option lookup: https://home-manager-options.extranix.com. HM keeps no generations of its own here: rollback is the NixOS generation. Backups of home data are `my.backup` items.
