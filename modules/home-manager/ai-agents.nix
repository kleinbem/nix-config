{
  config,
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

  # The stolen idea from Omarchy: a single skill that teaches *any* coding
  # agent how this workspace is shaped, so it stops treating the meta-root as
  # a repo and knows the fan-out recipes / jj workflow / inventory before it
  # touches anything. Kept short on purpose — the deep detail lives in each
  # repo's own AGENTS.md and in nix-config/docs/*.md.
  fleetSkill = pkgs.writeText "kleinbem-fleet-SKILL.md" ''
    ---
    name: kleinbem-fleet
    description: >-
      Orientation for the kleinbem NixOS + OpenWrt fleet: the workspace root is
      not a repo, the three conductors, fleet-wide `just` fan-out, jj-first VCS,
      the master inventory, and the standalone-container model. Load before
      working anywhere under ~/Develop/github.com/kleinbem.
    ---
    # kleinbem fleet

    ## The workspace root is not a repo

    `~/Develop/github.com/kleinbem/` is a flat directory of ~15 independent
    sibling git+jj repos (no submodules). `cd` into the specific repo before
    doing real work — each has its own `AGENTS.md`/`CLAUDE.md` with the detail
    that matters. The root is only for orientation and fleet-wide fan-out.

    ## The three conductors

    Tooling-only orchestrators, no `flake.nix` of their own (except `kleinbem/`):

    - **`kleinbem/`** — fleet hub. Owns `repos.nix` (every repo + its GitHub
      URL), the canonical `.just/common.just` + `.just/jj.just`, and
      `tools/jj-fleet.sh` (dashboard).
    - **`nix/`** — conductor for the Nix side. Real work: `nix-config` (hosts,
      modules, inventory — start here for NixOS questions), `nix-presets`
      (shared service/desktop bundles), `nix-hardware`, `nix-devshells`,
      `nix-packages`, `nix-templates`.
    - **`openwrt/`** — conductor for the router side. Real work:
      `openwrt-builder` (firmware images, profile `bpi-r4`) and
      `openwrt-config` (Ansible runtime config).

    Other repos: `github-config` (Terraform-managed GitHub org settings),
    `kleinbem-secrets` (current sops+age secrets store — replaces the legacy
    `nix-secrets`/`openwrt-secrets`), `kleinbem-site` (kleinbem.dev),
    `kleinbem-auth` (visitor login service).

    ## Fleet-wide commands

    Run from anywhere in the workspace; `filter` substring-matches repo names:

    ```
    just status-all [filter]        # repo state + ahead-of-origin counts
    just diff-all [filter]          # uncommitted changes fleet-wide
    just remote-status [filter]     # CI / PRs / issues (hits gh API)
    just ship-all "msg" [filter]    # save-all + sign-unsigned + push-all
    just in <repo> <recipe>         # pass through to one repo's justfile
                                    #   e.g. just in nix-config nixos::switch
    ```

    ## VCS is jj-first

    Jujutsu is the primary interface (colocated with git). Use raw `git` only
    for rescue / destructive resets not wrapped by the `jj::*` recipes. A bare
    `jj git push` no-ops here — push via `just jj::push-all <filter>` from a
    conductor. When no YubiKey is attached, avoid `jj` entirely: it
    auto-snapshots the working copy into a *signed* commit on nearly every
    command. Use plain `git` edits instead.

    ## nix-config specifics

    - Auto-generated ground-truth, refreshed by `just maintenance::sync-agent`:
      `docs/OPTIONS.md` (every `my.*`/`modules.*` option + declaration site +
      opted-in hosts), `docs/IMPORTS.md` (per-host import map),
      `docs/SYSTEM_REFERENCE.md` (nixpkgs revs, hosts, services). Grep these
      first to see blast radius.
    - Every option lives under `my.*` (system) or `modules.*` (home-manager).
      Hosts default to `enable = false` and must explicitly opt in.
    - `inventory.nix` is the master source for **both** NixOS and OpenWrt;
      `openwrt-config/ansible/inventory.ini` is generated from it — never
      hand-edited.

    ## Standalone containers (ADR-002)

    No host evals its own container closures. `container-factory` builds them
    centrally; hosts pull to `/var/lib/machines/<name>/current`. Adding a
    deployed container = 3 edits: preset in `nix-presets`, host
    `containers.nix` opt-in, `container-factory` import + catalogue entry.

    ## Secrets

    `kleinbem-secrets` = sops + age, per-path scoped recipients. Never assume a
    plaintext file in a `*-secrets` repo is safe to read/edit/reference just
    because the repo is "the encrypted one" — verify first.

    ## Environment

    Each repo's `.envrc` loads a Nix devshell via direnv, ultimately
    `nix-devshells#workspace` (or `#openwrt`), providing `just`, `jj`, `gh`,
    `gum`, `sops`, `age`. If a tool seems missing from PATH, the devshell
    probably isn't loaded — check `direnv status` / `direnv allow`.
  '';

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
      description = "Fan the kleinbem-fleet skill into every agent's skills dir.";
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

      # One skill file, symlinked into each agent's skills directory.
      file = lib.mkIf cfg.skills.enable (
        lib.mkMerge (
          lib.mapAttrsToList (_: a: {
            "${a.skillDir}/kleinbem-fleet/SKILL.md".source = fleetSkill;
          }) agents
          ++ [
            # Emerging cross-agent convention (AGENTS.md ecosystem).
            { ".agents/skills/kleinbem-fleet/SKILL.md".source = fleetSkill; }
          ]
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
