# Keeps the Obsidian vault (~/Documents/Notes) self-maintaining instead of
# depending on remembering to run `just os notes::organize`/`link-docs` by
# hand: PARA foldering, distillation-candidate flagging, the AGENTS.md
# LLM-orientation index, and the fleet `.agent/`-knowledge symlinks all go
# stale the moment nobody thinks to run them manually.
#
# Host-specific (like ./caddy-ca-refresh.nix) rather than shared home.nix:
# it hardcodes the live git checkout path (not the nix-store-managed
# `~/.just` copy — same convention `notes.just`'s own `SCRIPTS` var uses,
# so editing the scripts in-repo takes effect without a rebuild), which
# only exists on this desktop. Other hosts don't have the vault or the
# fleet repos cloned at this path.
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
