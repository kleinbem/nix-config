{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.my.services.githubNotify;
  stateDir = "/var/lib/github-notify";

  notify = pkgs.writeShellApplication {
    name = "github-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      gh_token=$(cat ${lib.escapeShellArg cfg.githubTokenFile})
      topic=$(cat ${lib.escapeShellArg cfg.ntfy.topicFile})
      ntfy_auth=()
      if [ -r ${lib.escapeShellArg (toString cfg.ntfy.tokenFile)} ]; then
        ntfy_auth=(-H "Authorization: Bearer $(cat ${lib.escapeShellArg (toString cfg.ntfy.tokenFile)})")
      fi

      gh() {
        curl -fsS --max-time 30 \
          -H "Authorization: Bearer $gh_token" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" "$@"
      }

      # First run (or lost state): look back one poll window only, so a fresh
      # start doesn't replay the whole unread inbox.
      state=''${STATE_DIRECTORY:-${stateDir}}/since
      since=$(cat "$state" 2>/dev/null || date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

      # Only unread threads updated since the last poll, oldest first.
      gh "https://api.github.com/notifications?since=$since&per_page=50" \
        | jq -c --argjson quiet ${lib.escapeShellArg (builtins.toJSON cfg.quietOwners)} \
            --argjson quietReasons ${lib.escapeShellArg (builtins.toJSON cfg.quietOwnerReasons)} \
            --argjson reasons ${lib.escapeShellArg (builtins.toJSON cfg.reasons)} '
          reverse[]
          | select(
              if (.repository.owner.login | IN($quiet[])) then (.reason | IN($quietReasons[]))
              else (.reason | IN($reasons[])) end)' \
        | while read -r n; do
            repo=$(jq -r '.repository.full_name' <<<"$n")
            title=$(jq -r '.subject.title' <<<"$n")
            reason=$(jq -r '.reason' <<<"$n")
            # Link to the latest comment when there is one, else the PR/issue.
            api=$(jq -r '.subject.latest_comment_url // .subject.url // empty' <<<"$n")
            # CI notifications carry no subject URL; the Actions page is closest.
            click=https://github.com/$repo
            [ "$(jq -r '.subject.type' <<<"$n")" != CheckSuite ] || click=https://github.com/$repo/actions
            if [ -n "$api" ]; then
              click=$(gh "$api" | jq -r '.html_url // empty') || true
              [ -n "$click" ] || click=https://github.com/$repo
            fi
            case "$reason" in
              review_requested | assign | security_alert) prio=high ;;
              mention | team_mention) prio=high ;;
              *) prio=default ;;
            esac
            # The URL goes in the body too, so it shows and can be copied.
            curl -fsS --max-time 15 "''${ntfy_auth[@]}" \
              -H "Title: $repo" -H "Priority: $prio" -H "Tags: $reason" \
              -H "Click: $click" -H "Actions: view, Open, $click" \
              --data-binary "$title ($reason)"$'\n'"$click" \
              ${lib.escapeShellArg cfg.ntfy.url}/"$topic" >/dev/null
          done

      # Advance only after every message went out; a failed run retries the
      # same window next time.
      printf '%s\n' "$now" >"$state"
    '';
  };
in
{
  options.my.services.githubNotify = {
    enable = lib.mkEnableOption "forwarding of GitHub notifications to ntfy";

    githubTokenFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        File with a classic GitHub token that has only the `notifications`
        scope. Fine-grained tokens and GitHub App tokens can't read
        notifications.
      '';
    };

    ntfy = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://ntfy.kleinbem.dev";
      };
      topicFile = lib.mkOption {
        type = lib.types.str;
        description = "File holding the ntfy topic (a secret).";
      };
      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "File with an ntfy access token that may write the topic.";
      };
    };

    reasons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "review_requested"
        "assign"
        "security_alert"
        "mention"
        "team_mention"
        "author"
        "comment"
        "state_change"
      ];
      description = "Notification reasons forwarded for repositories of other owners (upstream work).";
    };

    quietOwners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "kleinbem"
        "kleinbem-dev"
      ];
      description = ''
        Owners whose repositories only forward `quietOwnerReasons`. On our own
        repos, author and mention notifications are mostly bots (CodeRabbit,
        Dependabot) on agent-opened PRs.
      '';
    };

    quietOwnerReasons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "review_requested"
        "assign"
        "security_alert"
      ];
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Poll interval (systemd time span).";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      systemd.services.github-notify = {
        description = "Forward GitHub notifications to ntfy";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe notify;
          StateDirectory = "github-notify";
          DynamicUser = false;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
      systemd.timers.github-notify = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.interval;
        };
      };
    }
    # The poll cursor, so a reboot (tmpfs /var) neither replays nor skips.
    // lib.optionalAttrs (options.environment ? persistence) {
      environment.persistence."/nix/persist".directories = [ stateDir ];
    }
  );
}
