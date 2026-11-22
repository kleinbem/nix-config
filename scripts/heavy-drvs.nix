# scripts/heavy-drvs.sh as a package, for the host-side gates
# (my.deploy.autoUpgrade.localAssembly, my.deploy.comin.localAssembly).
{
  writeShellApplication,
  nix,
  jq,
  gnused,
  gnugrep,
}:
writeShellApplication {
  name = "heavy-drvs";
  runtimeInputs = [
    nix
    jq
    gnused
    gnugrep
  ];
  text = builtins.readFile ./heavy-drvs.sh;
}
