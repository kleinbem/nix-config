# Runs the `notes::organize`/`link-docs` maintenance on the Obsidian vault
# daily so it doesn't depend on someone remembering.
# Host-specific: it runs the scripts from the live checkout (edits apply
# without a rebuild), which only exists on this desktop.
{ config, pkgs, ... }:
let
  scripts = "${config.home.homeDirectory}/Develop/github.com/kleinbem/nix-config/users/martin/files/scripts";

  runScript = pkgs.writeShellScript "notes-maintenance" ''
    set -euo pipefail
    ${pkgs.bash}/bin/bash "${scripts}/link-docs-to-obsidian.sh"
    ${pkgs.nushell}/bin/nu "${scripts}/organize-notes.nu"
  '';
in
{
  systemd.user.services.notes-maintenance = {
    Unit.Description = "Organize Obsidian vault, relink fleet .agent/ knowledge, regenerate AGENTS.md";
    Service = {
      Type = "oneshot";
      ExecStart = "${runScript}";
    };
  };

  systemd.user.timers.notes-maintenance = {
    Unit.Description = "Periodically run Obsidian vault maintenance";
    Timer = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1d";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
