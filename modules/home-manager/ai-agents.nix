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
    # goose reads ~/.agents/skills itself (plus ~/.claude/skills and
    # ~/.config/goose/skills), so it needs no skills dir of its own: a second
    # link would list every skill twice.
    goose = {
      exe = "goose";
      package = pkgs.goose-cli;
      skillDir = null;
    };
  };

  defaultExe = agents.${cfg.defaultAgent}.exe;

  # The MCP servers nix-presets' modules.mcp registers for every other client
  # (claude desktop, gemini, antigravity …), as goose stdio extensions, so
  # goose gets the same tools. Keyed by server name; goose.settings wins on
  # conflicts, e.g. to disable one. `cmd` may be a bare program (atlas): goose
  # resolves it from PATH like the other clients do.
  mcpServers = lib.optionalAttrs (lib.attrByPath [ "modules" "mcp" "enable" ] false config) (
    lib.attrByPath [ "modules" "mcp" "servers" ] { } config
  );
  gooseMcpExtensions = lib.mapAttrs (name: server: {
    type = "stdio";
    inherit name;
    enabled = true;
    cmd = server.command;
    inherit (server) args;
    envs = server.env;
    env_keys = [ ];
    timeout = 300;
  }) mcpServers;
  gooseFinalSettings = lib.recursiveUpdate (lib.optionalAttrs cfg.goose.mcpExtensions {
    extensions = gooseMcpExtensions;
  }) cfg.goose.settings;

  # Every agent we must put on PATH: the default plus any explicit extras.
  wantedAgents = lib.unique ([ cfg.defaultAgent ] ++ cfg.installAgents);
  agentPackages =
    lib.filter (p: p != null) (map (name: agents.${name}.package) wantedAgents)
    ++ lib.optionals (builtins.elem "goose" wantedAgents) cfg.goose.extraPackages;

  # Every skill in the kleinbem/skills repo (a Claude Code plugin marketplace:
  # plugins/<plugin>/skills/<skill>/SKILL.md), fanned out to every agent below.
  # kleinbem-fleet teaches any agent how this workspace is shaped; the deep
  # detail lives in each repo's AGENTS.md and in nix-config/docs/*.md.
  skillsRepo = inputs.kleinbem-skills;
  # Plus the upstream Home Assistant skills (homeassistant-ai/skills, the
  # ha-mcp authors' marketplace: skills/<skill>/SKILL.md at the repo root).
  # They teach the agent HA automation/helper/dashboard conventions for the
  # home-assistant MCP server (modules.mcp.homeAssistant).
  haSkillsRepo = inputs.home-assistant-skills;
  skills =
    lib.concatMapAttrs (
      plugin: _:
      let
        dir = "${skillsRepo}/plugins/${plugin}/skills";
      in
      lib.mapAttrs (skill: _: "${dir}/${skill}") (builtins.readDir dir)
    ) (builtins.readDir "${skillsRepo}/plugins")
    // lib.mapAttrs (skill: _: "${haSkillsRepo}/skills/${skill}") (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${haSkillsRepo}/skills")
    );

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

    claude.settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        permissions.defaultMode = "auto";
      };
      description = ''
        Keys to enforce in ~/.claude/settings.json. Claude Code writes to that
        file itself, so it stays a real file: on every activation these keys
        are deep-merged over it (lists are replaced, not appended) and every
        key not declared here is left alone.
      '';
    };

    goose = {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = lib.literalExpression ''
          {
            active_provider = "claude-acp";
            providers.claude-acp = {
              enabled = true;
              configured = true;
              model = "current";
            };
            extensions.buzz = {
              type = "stdio";
              name = "buzz";
              enabled = true;
              cmd = lib.getExe pkgs.buzz-dev-mcp;
              args = [ ];
              timeout = 300;
            };
          }
        '';
        description = ''
          Keys to enforce in ~/.config/goose/config.yaml (provider, extensions,
          GOOSE_* settings). goose writes that file itself (`goose configure`,
          provider migrations), so it stays a real file: on every activation
          these keys are deep-merged over it (lists are replaced, not appended)
          and every key not declared here is left alone. API keys never belong
          here; goose ignores them in config.yaml (keyring or env instead).
        '';
      };

      mcpExtensions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Register every server of `modules.mcp` (nix-presets) as a goose stdio
          extension, keyed by its name, so goose has the same tools as the other
          clients. Override single ones in `goose.settings.extensions.<name>`.
        '';
      };

      finalSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        readOnly = true;
        description = "What the activation merges into goose's config.yaml: the MCP extensions plus `goose.settings`.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.claude-agent-acp ]";
        description = ''
          Packages goose needs on PATH next to itself, such as the ACP adapter
          of the provider in `goose.settings` (goose resolves `claude-agent-acp`
          and friends from PATH). Only installed when goose is a selected agent.
        '';
      };
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
          ) (lib.filter (d: d != null) (lib.mapAttrsToList (_: a: a.skillDir) agents) ++ [ ".agents/skills" ])
        )
      );
    };

    # Same reason as herdr's config.toml (nix-presets/herdr.nix): a store
    # symlink would make Claude Code's own writes fail, so merge instead.
    home.activation.claudeSettings = lib.mkIf (cfg.claude.settings != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settingsPath="${config.home.homeDirectory}/.claude/settings.json"
        declared=${pkgs.writeText "claude-settings.json" (builtins.toJSON cfg.claude.settings)}
        if [ -L "$settingsPath" ]; then
          run rm -f "$settingsPath"
        fi
        if [ -s "$settingsPath" ] && ${pkgs.jq}/bin/jq -e 'type == "object"' "$settingsPath" >/dev/null 2>&1; then
          tmp=$(mktemp)
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settingsPath" "$declared" > "$tmp"
          run install -m644 "$tmp" "$settingsPath"
          rm -f "$tmp"
        else
          if [ -e "$settingsPath" ]; then
            run mv "$settingsPath" "$settingsPath.invalid"
          fi
          run install -Dm644 "$declared" "$settingsPath"
        fi
      ''
    );

    # Same merge for goose's config.yaml (YAML, so yq instead of jq).
    modules.ai-agents.goose.finalSettings = gooseFinalSettings;

    home.activation.gooseSettings = lib.mkIf (gooseFinalSettings != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settingsPath="${config.home.homeDirectory}/.config/goose/config.yaml"
        declared=${pkgs.writeText "goose-config.yaml" (builtins.toJSON gooseFinalSettings)}
        if [ -L "$settingsPath" ]; then
          run rm -f "$settingsPath"
        fi
        if [ -s "$settingsPath" ] && ${pkgs.yq-go}/bin/yq -e 'type == "!!map"' "$settingsPath" >/dev/null 2>&1; then
          tmp=$(mktemp)
          ${pkgs.yq-go}/bin/yq eval-all '. as $item ireduce ({}; . * $item)' "$settingsPath" "$declared" > "$tmp"
          run install -m644 "$tmp" "$settingsPath"
          rm -f "$tmp"
        else
          if [ -e "$settingsPath" ]; then
            run mv "$settingsPath" "$settingsPath.invalid"
          fi
          tmp=$(mktemp)
          ${pkgs.yq-go}/bin/yq -P '.' "$declared" > "$tmp"
          run install -Dm644 "$tmp" "$settingsPath"
          rm -f "$tmp"
        fi
      ''
    );

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
