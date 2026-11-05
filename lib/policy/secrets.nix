# disabled-feature-has-no-owned-secrets: sops-install-secrets materialises
# every declared secret at activation, so a secret for a feature that is off
# fails the switch until its key exists.
#
# Two directions:
# - per host: a secret or template belongs to the feature its name starts with
#   (`litellm_master_key` → my.containers.litellm, `garage-ui.env` →
#   garage-ui), and that feature must be on wherever it's declared;
# - default-off: all modules imported, nothing enabled, must declare only the
#   baseline; enabling a feature must declare its secret (the canaries).
{ lib }:
let
  # Credentials for a service that runs elsewhere in the fleet, not for the
  # local feature of the same name.
  clientSecrets = {
    attic_pull_token = "reads the private Attic cache on core-pi (attic-pull.nix)";
    attic_push_token = "pushes builds to the Attic cache on core-pi";
    "attic-netrc" = "attic-pull.nix's netrc for the Attic cache on core-pi";
    ntfy_alert_topic = "alert topic on ntfy.kleinbem.dev (audit.nix, backup.nix)";
    ntfy_deploy_topic = "deploy topic on ntfy.kleinbem.dev (auto-upgrade.nix)";
  };

  # Declared by every host that imports the module tier, nothing to enable:
  # each host must provision these keys.
  baseline = {
    nix_signing_key = "core.nix: fleet build-signing key";
    ntfy_alert_topic = "audit.nix: security alerts from every workstation-tier host";
    root_password_hash = "users.nix: root password on workstation-tier hosts";
  };

  # A feature enabled here must declare this secret, or the default-off
  # result above means nothing.
  canaries = [
    {
      module.my.heartbeat.enable = true;
      expect = "healthchecks_ping_key";
    }
  ];

  # meshLlm → mesh_llm, garage-ui → garage_ui, so names compare as one form.
  normalise =
    s:
    lib.toLower (
      lib.concatMapStrings (
        c:
        if c == "-" || c == "." then
          "_"
        else if lib.toUpper c == c && lib.toLower c != c then
          "_${c}"
        else
          c
      ) (lib.stringToCharacters s)
    );

  # Template file names belong to their stem: "litellm.env" → litellm.
  stem = name: lib.head (lib.splitString "." name);

  groupsOf = cfg: [
    cfg.my
    (cfg.my.containers or { })
    (cfg.my.services or { })
  ];

  # Every my.<x>, my.containers.<x> and my.services.<x> with an enable flag,
  # taken from the default-off config so features a host doesn't import count.
  features =
    cfg:
    lib.unique (
      lib.concatMap (g: lib.attrNames (lib.filterAttrs (_: v: builtins.isAttrs v && v ? enable) g)) (
        groupsOf cfg
      )
    );

  enabledOn = cfg: name: lib.any (g: ((g.${name} or { }).enable or false) == true) (groupsOf cfg);

  # Longest feature name the secret name starts with.
  ownerOf =
    feats: secret:
    let
      k = normalise (stem secret);
      matches = lib.filter (f: k == normalise f || lib.hasPrefix "${normalise f}_" k) feats;
    in
    lib.foldl' (
      best: f: if best == null || lib.stringLength f > lib.stringLength best then f else best
    ) null matches;

  names = cfg: {
    secrets = lib.attrNames cfg.sops.secrets;
    templates = lib.attrNames cfg.sops.templates;
  };

  # [{ host, kind, name, owner }] for secrets whose owner is off on the host.
  orphans =
    feats: hosts:
    lib.concatLists (
      lib.mapAttrsToList (
        host: cfg:
        let
          hostFeats = lib.unique (feats ++ features cfg);
        in
        lib.concatLists (
          lib.mapAttrsToList (
            kind: ns:
            lib.concatMap (
              name:
              let
                owner = ownerOf hostFeats name;
              in
              lib.optional (owner != null && !enabledOn cfg owner) {
                inherit
                  host
                  kind
                  name
                  owner
                  ;
              }
            ) ns
          ) (names cfg)
        )
      ) hosts
    );

  declared = cfg: lib.attrNames cfg.sops.secrets ++ lib.attrNames cfg.sops.templates;
in
{
  # hosts: { name = config; }; defaultOff: extra module → config with every
  # nix-config module imported.
  violations =
    hosts: defaultOff:
    let
      off = defaultOff { };
      feats = features off;
      found = orphans feats hosts;
      got = declared off;
    in
    map (
      o:
      "${o.host}: sops.${o.kind}.\"${o.name}\" is declared but `${o.owner}` is disabled there; gate it on that feature's enable"
    ) (lib.filter (o: !(clientSecrets ? ${o.name})) found)
    ++ map (n: "clientSecrets.\"${n}\" in lib/policy/secrets.nix matches no host; drop it") (
      lib.subtractLists (map (o: o.name) found) (lib.attrNames clientSecrets)
    )
    ++ map (
      n:
      "default-off config declares sops \"${n}\" with nothing enabled; gate it on its module's enable, or add it to `baseline` in lib/policy/secrets.nix"
    ) (lib.subtractLists (lib.attrNames baseline) got)
    ++ map (n: "baseline.\"${n}\" in lib/policy/secrets.nix is no longer declared; drop it") (
      lib.subtractLists got (lib.attrNames baseline)
    )
    ++ lib.concatMap (
      c:
      lib.optional (!lib.elem c.expect (declared (defaultOff c.module)))
        "canary: enabling ${builtins.toJSON c.module} no longer declares \"${c.expect}\"; the check would miss ungated secrets"
    ) canaries;
}
