# host-key-directories-are-root-only + dynamic-user-private-directory-mode.
#
# Every tmpfiles entry for these directories must be `d` (or `z`) 0700
# root:root, and at least one must exist. host-secrets.nix holds plaintext
# initrd keys; /var/lib/private must stay 0700 or systemd refuses to start
# DynamicUser services, and impermanence creates it 0755 when it persists a
# directory below it.
{ lib, common }:
hostName: cfg:
let
  entries = common.tmpfilesEntries cfg;
  rootOnly =
    e:
    lib.elem e.type [
      "d"
      "z"
    ]
    && e.mode == "0700"
    && e.user == "root"
    && e.group == "root";

  expectRootOnly =
    path: why:
    let
      forPath = lib.filter (e: e.path == path) entries;
      persisted = lib.filter (d: d.directory == path) (common.persistedDirs cfg);
    in
    lib.optional (
      !lib.any rootOnly forPath
    ) "${hostName}: no tmpfiles `d ${path} 0700 root root` (${why})"
    ++ map (
      e:
      "${hostName}: ${e.src} sets `${e.type} ${path} ${e.mode} ${e.user} ${e.group}`, must be d 0700 root root (${why})"
    ) (lib.filter (e: !rootOnly e) forPath)
    ++ map (
      d:
      "${hostName}: impermanence persists ${path} as ${d.mode} ${d.user}:${d.group}, must be 0700 root:root (${why})"
    ) (lib.filter (d: !(d.mode == "0700" && d.user == "root" && d.group == "root")) persisted);

  hostKeys = lib.optionals (cfg.my ? hostSecrets) (
    let
      inherit (cfg.my.hostSecrets) dir;
    in
    expectRootOnly dir "host-secrets.nix: plaintext host keys"
    ++ expectRootOnly "${dir}/initrd" "host-secrets.nix: initrd SSH and LUKS keys"
    ++ lib.optional (
      !common.isPersistent cfg dir
    ) "${hostName}: ${dir} is on tmpfs, host keys would vanish on reboot"
  );

  # impermanence creates missing parents 0755, so any persisted directory
  # below /var/lib/private needs the 0700 fix on both sides of the bind.
  privateDirs = lib.filter (d: lib.hasPrefix "/var/lib/private/" d.directory) (
    common.persistedDirs cfg
  );
  privateRoots = lib.unique (
    [ "/var/lib/private" ] ++ map (d: "${d.persistentStoragePath}/var/lib/private") privateDirs
  );
  dynamicUser = lib.optionals (privateDirs != [ ]) (
    lib.concatMap (p: expectRootOnly p "DynamicUser state root") privateRoots
  );
in
hostKeys ++ dynamicUser
