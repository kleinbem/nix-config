# Standalone containers run the closure hosts/container-factory builds, so a
# `my.containers.<name>` setting on the deploying host only takes effect if
# the factory has it too. For every deployed container this rebuilds the
# factory's closure with the host's settings and compares the derivations.
# Run it with the real secrets too: CI's dummies switch off whatever a host
# gates on a secret.
{ lib }:
{
  # hosts, factory: evaluated nixosConfigurations (one system).
  # realNames: option name -> container names, where they differ.
  # known: "<host>/<container>" pairs that differ today.
  hosts,
  factory,
  realNames,
  known,
}:
let
  optionOf =
    name: lib.findFirst (o: lib.elem name (realNames.${o} or [ ])) name (lib.attrNames realNames);

  # Packages stay the factory's: their defaults come from each system's own
  # pkgs, and the factory carries overlays the hosts don't need.
  hostSettings =
    host: o: lib.filterAttrs (_: v: !(lib.isDerivation v)) host.config.my.containers.${o};

  pairs = lib.concatLists (
    lib.mapAttrsToList (
      hostName: host:
      let
        names = host.config.services.nix-gantry.updater.containers or [ ];
        withHostSettings = factory.extendModules {
          modules = [
            {
              my.containers = lib.genAttrs (map optionOf names) (
                o: lib.mkForce (hostSettings host o // { enable = true; })
              );
            }
          ];
        };
        drv =
          system: name: builtins.unsafeDiscardStringContext system.config.containers.${name}.path.drvPath;
        differing =
          o:
          lib.filter (
            k:
            let
              same = builtins.tryEval (
                host.config.my.containers.${o}.${k} == factory.config.my.containers.${o}.${k}
              );
            in
            !(same.success && same.value)
          ) (lib.attrNames (hostSettings host o));
      in
      map (name: {
        id = "${hostName}/${name}";
        same = drv factory name == drv withHostSettings name;
        options = differing (optionOf name);
      }) names
    ) hosts
  );

  ids = map (p: p.id) pairs;
  # `known` covers both systems; only this system's hosts are judged here.
  knownHere = lib.filter (id: hosts ? ${lib.head (lib.splitString "/" id)}) known;
in
map (
  p:
  "${p.id}: the host's my.containers settings build a different closure than hosts/container-factory, which is the one deployed. Set them in the factory catalogue. Options that differ (data dirs, secret paths and limits are host-side and harmless): ${lib.concatStringsSep ", " p.options}"
) (lib.filter (p: !p.same && !(lib.elem p.id known)) pairs)
++ map (p: "${p.id}: matches the factory now; remove it from the known list") (
  lib.filter (p: p.same && lib.elem p.id known) pairs
)
++ map (id: "${id}: in the known list but not a deployed container; remove it") (
  lib.filter (id: !(lib.elem id ids)) knownHere
)
