# Helpers shared by the policy checks: they read evaluated host configs only,
# so every check stays eval-level (no host builds).
{ lib }:
rec {
  # `dir` is `path` or one of its parents.
  covers = dir: path: dir == "/" || path == dir || lib.hasPrefix "${lib.removeSuffix "/" dir}/" path;

  # Deepest fileSystems entry containing `path`; null if none.
  mountOf =
    cfg: path:
    lib.foldl' (
      best: fs:
      if
        covers fs.mountPoint path
        && (best == null || lib.stringLength fs.mountPoint > lib.stringLength best.mountPoint)
      then
        fs
      else
        best
    ) null (lib.attrValues cfg.fileSystems);

  # On RAM: under a tmpfs mount, or under no mount at all.
  onTmpfs =
    cfg: path:
    let
      fs = mountOf cfg path;
    in
    fs == null || fs.fsType == "tmpfs";

  persistence = cfg: lib.attrValues (cfg.environment.persistence or { });

  # Every impermanence directory entry, with its storage root.
  persistedDirs = cfg: lib.concatMap (p: p.directories) (persistence cfg);
  persistedFiles = cfg: lib.concatMap (p: p.files) (persistence cfg);

  # Survives a reboot: an impermanence entry covers it, or it sits on a disk.
  isPersistent =
    cfg: path:
    lib.any (d: covers d.directory path) (persistedDirs cfg)
    || lib.any (f: f.file == path) (persistedFiles cfg)
    || !(onTmpfs cfg path);

  # tmpfiles entries from both `rules` and `settings`, as
  # { path, type, mode, user, group, src }.
  tmpfilesEntries =
    cfg:
    let
      fromRule =
        rule:
        let
          f = lib.filter (s: s != "") (lib.splitString " " (lib.replaceStrings [ "\t" ] [ " " ] rule));
          at = i: if lib.length f > i then lib.elemAt f i else "-";
        in
        lib.optional (lib.length f >= 2) {
          type = at 0;
          path = at 1;
          mode = at 2;
          user = at 3;
          group = at 4;
          src = "rule \"${rule}\"";
        };
      fromSettings = lib.concatLists (
        lib.mapAttrsToList (
          file: paths:
          lib.concatLists (
            lib.mapAttrsToList (
              path: types:
              lib.mapAttrsToList (type: e: {
                inherit path type;
                mode = e.mode or "-";
                user = e.user or "-";
                group = e.group or "-";
                src = "settings.${file}";
              }) types
            ) paths
          )
        ) cfg.systemd.tmpfiles.settings
      );
    in
    lib.concatMap fromRule cfg.systemd.tmpfiles.rules ++ fromSettings;

  # A failing check prints its violations; a clean one is an empty output.
  # `nix eval .#checks.<system>.policy-<name>.violations` lists them too.
  mkCheck =
    pkgs: name: violations:
    if violations == [ ] then
      pkgs.runCommandLocal "policy-${name}" { passthru = { inherit violations; }; } "touch $out"
    else
      pkgs.runCommandLocal "policy-${name}"
        {
          report = lib.concatMapStrings (v: "  - ${v}\n") violations;
          passAsFile = [ "report" ];
          passthru = { inherit violations; };
        }
        ''
          echo "policy-${name}: ${toString (lib.length violations)} violation(s):" >&2
          cat "$reportPath" >&2
          exit 1
        '';
}
