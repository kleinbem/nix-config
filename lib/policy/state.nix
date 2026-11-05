# required-state-has-persistent-storage: / (and so /var) is tmpfs on every
# host, so state left there is lost on reboot and fills RAM until then.
# Every StateDirectory of an enabled unit and every enabled container's
# hostDataDir must be covered by an impermanence entry or sit on a disk.
{ lib, common }:
let
  # State that may vanish on reboot. Keys are "<host>:<path>" or "*:<path>";
  # each needs a reason.
  disposable = {
    "*:/var/lib/systemd/linger" = "linger-users recreates it from users.users.*.linger at boot";
    "*:/var/lib/geoclue" = "location cache, refetched";
    "nixos-nvme:/var/lib/btrfs" = "btrfs-scrub status files only";
    "nixos-nvme:/var/lib/dnsmasq" = "ai-hardening.nix's DNS forwarder; no DHCP leases";
    "orin-nano:/var/lib/github-runner/mesh-llm-gpu" = "ephemeral runner, registers again for every job";
  };

  stateDirsOf =
    name: svc:
    let
      sc = svc.serviceConfig or { };
      raw = sc.StateDirectory or [ ];
      dirs = lib.filter (s: s != "") (
        lib.concatMap (lib.splitString " ") (if builtins.isList raw then raw else [ raw ])
      );
      dynamic = lib.elem (sc.DynamicUser or false) [
        true
        "yes"
        "true"
      ];
      # "a:b" makes a and links b to it; the data lives in a.
      base = s: lib.head (lib.splitString ":" s);
    in
    lib.optionals (svc.enable or true) (
      map (d: {
        path = (if dynamic then "/var/lib/private/" else "/var/lib/") + base d;
        what = "systemd.services.${name} StateDirectory${lib.optionalString dynamic " (DynamicUser)"}";
      }) dirs
    );

  containerDirsOf =
    name: c:
    lib.optional ((c.enable or false) && (c.hostDataDir or null) != null) {
      path = c.hostDataDir;
      what = "my.containers.${name}.hostDataDir";
    };

  required =
    cfg:
    lib.concatLists (lib.mapAttrsToList stateDirsOf cfg.systemd.services)
    ++ lib.concatLists (lib.mapAttrsToList containerDirsOf (cfg.my.containers or { }));

  allowed = hostName: path: disposable ? "${hostName}:${path}" || disposable ? "*:${path}";

  hint =
    path:
    if lib.hasPrefix "/var/lib/private/" path then
      "persist ${path} (DynamicUser: not the /var/lib symlink)"
    else
      "persist it in environment.persistence or move it to a data disk";

  hostViolations =
    hostName: cfg:
    map (r: "${hostName}: ${r.what} = ${r.path} is on tmpfs; ${hint r.path}") (
      lib.filter (r: !common.isPersistent cfg r.path && !allowed hostName r.path) (required cfg)
    );

  # Allowlist keys that no host needs any more.
  used =
    hosts:
    lib.concatLists (
      lib.mapAttrsToList (
        hostName: cfg:
        lib.concatMap (
          r:
          lib.optionals (!common.isPersistent cfg r.path) [
            "${hostName}:${r.path}"
            "*:${r.path}"
          ]
        ) (required cfg)
      ) hosts
    );
in
{
  inherit required;
  violations =
    hosts:
    lib.concatLists (lib.mapAttrsToList hostViolations hosts)
    ++ map (k: "disposable.\"${k}\" in lib/policy/state.nix matches no tmpfs state; drop it") (
      lib.subtractLists (used hosts) (lib.attrNames disposable)
    );
}
