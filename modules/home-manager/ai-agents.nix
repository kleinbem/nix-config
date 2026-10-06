{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.ai-agents;

  # Data-driven agent table. `exe` is what actually gets launched; `skillDir`
  # is that agent's on-disk skills location (relative to $HOME); `package` is
  # what to add to PATH when the agent is selected (null = supplied elsewhere,
  # e.g. opencode comes from `modules.opencode`). Omarchy 4 ("Quattro")
  # symlinks one skill file into each skillDir and installs the picked agent
  # on first run — we do both, declaratively.
  agents = {
    claude = {
      exe = "claude";
      package = pkgs.claude-code;
      skillDir = ".claude/skills";
    };
    opencode = {
      exe = "opencode";
      package = null; # provided by modules.opencode (self-updating `nix run`)
      skillDir = ".config/opencode/skills";
    };
    gemini = {
      exe = "gemini";
      package = pkgs.gemini-cli;
      skillDir = ".gemini/config/skills";
    };
    codex = {
      exe = "codex";
      package = pkgs.codex;
      skillDir = ".codex/skills";
    };
  };

  defaultExe = agents.${cfg.defaultAgent}.exe;

  # Every agent we must put on PATH: the default plus any explicit extras.
  wantedAgents = lib.unique ([ cfg.defaultAgent ] ++ cfg.installAgents);
  agentPackages = lib.filter (p: p != null) (map (name: agents.${name}.package) wantedAgents);

  # Every skill in the kleinbem/skills repo (a Claude Code plugin marketplace:
  # plugins/<plugin>/skills/<skill>/SKILL.md), fanned out to every agent below.
  # kleinbem-fleet teaches any agent how this workspace is shaped; the deep
  # detail lives in each repo's AGENTS.md and in nix-config/docs/*.md.
  skillsRepo = inputs.kleinbem-skills;
  skills = lib.concatMapAttrs (
    plugin: _:
    let
      dir = "${skillsRepo}/plugins/${plugin}/skills";
    in
    lib.mapAttrs (skill: _: "${dir}/${skill}") (builtins.readDir dir)
  ) (builtins.readDir "${skillsRepo}/plugins");

  # `agent` — launch the configured default agent. Omarchy calls its
  # equivalent `a`; we ship both.
  agentBin = pkgs.writeShellScriptBin "agent" ''
    exec ${defaultExe} "$@"
  '';

  # `crash-to-agent [program]` — hand the most recent coredump (optionally for
  # a named program) to the default agent for triage. Report goes to a
  # runtime file so the working dir stays clean and any agent can read it.
  crashToAgentBin = pkgs.writeShellScriptBin "crash-to-agent" ''
    set -euo pipefail
    prog="''${1:-}"
    report="''${XDG_RUNTIME_DIR:-/tmp}/omni-crash-report.md"
    {
      echo "# Coredump report''${prog:+ — $prog}"
      echo
      echo '```'
      if [ -n "$prog" ]; then
        ${pkgs.systemd}/bin/coredumpctl info "$prog" 2>&1 | head -300
      else
        ${pkgs.systemd}/bin/coredumpctl info 2>&1 | head -300
      fi
      echo '```'
    } > "$report"
    echo "Wrote $report"
    exec ${defaultExe} "Read $report — it is a systemd coredump report. Diagnose the crash and suggest a concrete fix."
  '';
in
{
  options.modules.ai-agents = {
    enable = lib.mkEnableOption "Omarchy-style cross-agent AI integration (default-agent launcher, fleet skill fan-out, crash-to-agent handoff)";

    defaultAgent = lib.mkOption {
      type = lib.types.enum (lib.attrNames agents);
      default = "claude";
      description = ''
        Which agent CLI `agent` / `a` / `crash-to-agent` invoke. Its package
        is put on PATH automatically (see `installAgents`); `opencode` is the
        exception — it must come from `modules.opencode.enable`.
      '';
    };

    installAgents = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames agents));
      default = [ ];
      example = [
        "gemini"
        "codex"
      ];
      description = ''
        Extra agent CLIs to put on PATH alongside the default. The default
        agent is always installed; list here any others you want available
        without dropping into a devshell.
      '';
    };

    skills.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Link every skill from the kleinbem/skills repo into every agent's skills dir.";
    };

    crashHandler.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install `crash-to-agent` and a user service that desktop-notifies
        when systemd-coredump logs a crash.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # opencode is the one agent this module doesn't package itself.
    assertions = [
      {
        assertion = !(builtins.elem "opencode" wantedAgents) || (config.modules.opencode.enable or false);
        message = "modules.ai-agents: opencode is selected but modules.opencode.enable is false — nothing puts `opencode` on PATH.";
      }
    ];

    home = {
      packages = [
        agentBin
      ]
      ++ agentPackages
      ++ lib.optionals cfg.crashHandler.enable [
        crashToAgentBin
        pkgs.libnotify
      ];

      shellAliases.a = "agent";

      sessionVariables.OMNI_DEFAULT_AGENT = defaultExe;

      # Each skill linked into each agent's skills directory, plus .agents/skills
      # (emerging cross-agent convention, AGENTS.md ecosystem). recursive keeps
      # a real directory per skill with its files linked inside.
      file = lib.mkIf cfg.skills.enable (
        lib.mkMerge (
          lib.concatMap (
            skillDir:
            lib.mapAttrsToList (skill: source: {
              "${skillDir}/${skill}" = {
                inherit source;
                recursive = true;
              };
            }) skills
          ) (lib.mapAttrsToList (_: a: a.skillDir) agents ++ [ ".agents/skills" ])
        )
      );
    };

    # Follow the system journal for coredumps and nudge toward crash-to-agent.
    # No privilege needed: martin is in `wheel`, which can read the journal.
    systemd.user.services.omni-crash-watch = lib.mkIf cfg.crashHandler.enable {
      Unit = {
        Description = "Notify on systemd-coredump crashes (hand to AI agent)";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = pkgs.writeShellScript "omni-crash-watch" ''
          ${pkgs.systemd}/bin/journalctl -f -b -n0 -t systemd-coredump -o cat \
          | while IFS= read -r line; do
              prog=$(printf '%s\n' "$line" \
                | ${pkgs.gnugrep}/bin/grep -oP 'Process [0-9]+ \(\K[^)]+' || true)
              ${pkgs.libnotify}/bin/notify-send -u critical -a crash-to-agent \
                "💥 ''${prog:-A process} crashed" \
                "Run: crash-to-agent ''${prog}"
            done
        '';
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
