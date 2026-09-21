# Shared "pull-deploy service node" profile: the pull-based fleet
# auto-upgrade config (modules/nixos/auto-upgrade.nix) plus its ntfy
# fast-path (deploy the moment promote-production publishes, instead of
# only at the fixed 04:00 window). Every 24/7 host in this tier
# (core-pi, hass-pi, nasbook, mac-mini) substitutes from Attic rather
# than compiling locally and wants the exact same values here.
#
# Extracted 2026-09-21: this used to be hand-duplicated per host (RPi5
# hosts got it via rpi5-node.nix, nasbook/mac-mini repeated it in their
# own default.nix) — which is exactly how nasbook/mac-mini silently ended
# up missing `ntfy.enable` for a while before anyone noticed. Import this
# instead of repeating the block, so the whole tier can only drift on
# purpose (a real per-host override), never by omission.
#
# Requires the importing host to also declare the ntfy_deploy_topic sops
# secret (a value already shared fleet-wide in nix/shared.yaml — see any
# importer's secrets.nix for the one-line declaration) — the ntfy
# listener is inert until that path exists, so this is safe to import
# even before that secret is declared.
_: {
  my.deploy.autoUpgrade = {
    enable = true;
    requireCache = true;
    ntfy.enable = true;
  };
}
