# VM test for hosts/core-pi/foyer-attention.nix: the sandboxed unit writes the
# feed from a stand-in GitHub API and keeps the last feed when the API is gone.
#   nix build .#checks.x86_64-linux.foyer-attention-test
{ pkgs, ... }:
let
  pr = {
    title = "fix the flux capacitor";
    html_url = "https://github.com/example/lab/pull/42";
    repository_url = "https://api.github.com/repos/example/lab";
    number = 42;
    updated_at = "2026-11-16T10:00:00Z";
  };
  checkRuns = runs: builtins.toJSON { check_runs = runs; };
  # Serves files by path; `?page=N` picks `<path>.pageN` when it exists. Every
  # search returns the same PR, since the query is otherwise ignored.
  server = pkgs.writeText "fake-github.py" ''
    import http.server, os, sys, urllib.parse

    root = sys.argv[1]

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            url = urllib.parse.urlsplit(self.path)
            base = os.path.join(root, url.path.lstrip("/"))
            page = urllib.parse.parse_qs(url.query).get("page", ["1"])[0]
            paged = f"{base}.page{page}"
            try:
                with open(paged if os.path.exists(paged) else base, "rb") as f:
                    body = f.read()
            except OSError:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    http.server.HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
  '';
  api = pkgs.runCommand "fake-github-api" { } ''
    mkdir -p $out/search $out/repos/kleinbem/nix-config/commits/HEAD $out/repos/kleinbem/nix-presets/commits/HEAD
    echo ${pkgs.lib.escapeShellArg (builtins.toJSON { items = [ pr ]; })} > $out/search/issues
    echo ${
      pkgs.lib.escapeShellArg (checkRuns [
        {
          name = "Build";
          conclusion = "failure";
          completed_at = "2026-11-16T11:00:00Z";
        }
        {
          name = "lint";
          conclusion = "success";
          completed_at = "2026-11-16T11:01:00Z";
        }
      ])
    } > $out/repos/kleinbem/nix-config/commits/HEAD/check-runs
    echo ${
      pkgs.lib.escapeShellArg (checkRuns [
        {
          name = "check";
          conclusion = "success";
          completed_at = "2026-11-16T11:00:00Z";
        }
      ])
    } > $out/repos/kleinbem/nix-presets/commits/HEAD/check-runs
  '';
in
pkgs.testers.runNixOSTest {
  name = "foyer-attention";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ ../hosts/core-pi/foyer-attention.nix ];

      # Declared by the dashboard preset on the real host.
      options.my.containers.dashboard.feedDir = lib.mkOption { type = lib.types.str; };

      config.systemd.services = {
        foyer-attention.environment.GITHUB_API = "http://127.0.0.1:8000";
        fake-github = {
          wantedBy = [ "multi-user.target" ];
          # A writable copy: the test rewrites responses.
          preStart = "rm -rf /run/fake-api && cp -r --no-preserve=mode ${api} /run/fake-api";
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${server} /run/fake-api";
        };
      };
    };

  testScript = ''
    feed = "/run/foyer-feed/attention.json"
    jq = "${pkgs.jq}/bin/jq -e "

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("fake-github.service")
    machine.wait_for_open_port(8000)
    machine.succeed("systemctl is-active foyer-attention.timer")

    with subtest("the sandboxed unit writes a world-readable feed as its own user"):
        machine.succeed("systemctl start foyer-attention.service")
        assert machine.succeed(f"stat -c '%U %a' {feed}").strip() == "foyer-feed 644"
        machine.succeed("test -z \"$(ls -A /run/foyer-feed | grep -v '^attention.json$')\"")

    with subtest("pull requests and failing default-branch checks become items"):
        machine.succeed(
            f"{jq} '[.items[] | select(.source == \"example/lab#42\") | .title] | sort == [\"Approved: fix the flux capacitor\", \"Changes requested: fix the flux capacitor\", \"Checks failing: fix the flux capacitor\", \"Review requested: fix the flux capacitor\"]' {feed}"
        )
        machine.succeed(
            f"{jq} '[.items[] | select(.source == \"CI\")] == [{{id: \"checks:kleinbem/nix-config\", title: \"kleinbem/nix-config: 1 failing on the default branch\", url: \"https://github.com/kleinbem/nix-config/actions\", detail: \"Build\", source: \"CI\", severity: \"critical\", updatedAt: \"2026-11-16T11:00:00Z\"}}]' {feed}"
        )
        machine.succeed(f"{jq} '(.items | length) == 5 and (.updatedAt | type) == \"string\"' {feed}")

    with subtest("items are ordered most severe first"):
        machine.succeed(
            f"{jq} '[.items[].severity] == [\"critical\", \"warning\", \"warning\", \"info\", \"info\"]' {feed}"
        )

    with subtest("a failed check on a later page of check runs is found"):
        runs = "/run/fake-api/repos/kleinbem/nix-presets/commits/HEAD/check-runs"
        machine.succeed(
            "${pkgs.jq}/bin/jq -n '{check_runs: [range(100) | {name: \"ok\\(.)\", conclusion: \"success\", completed_at: \"2026-11-16T11:00:00Z\"}]}'"
            f" > {runs}.page1"
        )
        machine.succeed(
            "echo '{\"check_runs\": [{\"name\": \"late\", \"conclusion\": \"failure\", \"completed_at\": \"2026-11-16T12:00:00Z\"}]}'"
            f" > {runs}.page2"
        )
        machine.succeed("systemctl start foyer-attention.service")
        machine.succeed(
            f"{jq} '[.items[] | select(.id == \"checks:kleinbem/nix-presets\") | .detail] == [\"late\"]' {feed}"
        )
        machine.succeed(f"{jq} '.items[0].id == \"checks:kleinbem/nix-presets\" and (.items | length) == 6' {feed}")

    with subtest("incomplete search results keep the previous feed"):
        before = machine.succeed(f"sha256sum {feed}")
        machine.succeed(
            "${pkgs.jq}/bin/jq '.incomplete_results = true | .items = []' /run/fake-api/search/issues > /run/fake-api/search/new"
            " && mv /run/fake-api/search/new /run/fake-api/search/issues"
        )
        machine.succeed("systemctl start foyer-attention.service")
        assert machine.succeed(f"sha256sum {feed}") == before

    with subtest("an unreachable API keeps the previous feed and does not fail the unit"):
        before = machine.succeed(f"sha256sum {feed}")
        machine.succeed("systemctl stop fake-github.service")
        machine.succeed("systemctl start foyer-attention.service")
        assert machine.succeed(f"sha256sum {feed}") == before
        machine.succeed("journalctl -u foyer-attention.service | grep -q 'keeping the previous feed'")
  '';
}
