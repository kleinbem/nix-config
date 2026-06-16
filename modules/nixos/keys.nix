{
  # Cachix Public Keys
  cachix = {
    nix-community = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
    devenv = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    cuda-maintainers = "cuda-maintainers.cachix.org-1:0dq3Anpl63anx7FsVnefPGowuE6gj7KE8txarwKScsu=";
    anduril = "anduril.cachix.org-1:0KJgGiAgDtCE9Pl0wvvyALRJlPhQMLRMMt+43JExFlY=";
  };

  # SSH Public Keys
  ssh = {
    yubikey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFLSRkt7uoF1c2iWpwt7mJi2krEtmpdUD4wLUm0XTn5JbGIBce+avhSqY02YRe3dpRVqo7KGE8upe11xI8IcEjk= PIV AUTH pubkey";
    # FIDO2 resident key (id_ed25519_sk) — works without PKCS11 and is offered by ssh-agent automatically
    fido2 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPbkLwSKFiip5e/0j9aHzIDr+4srK7s9C/aLbNOl7xJQAAAABHNzaDo=";
    # FIDO2 backup resident key
    fido2-backup = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINYunZXaiafJQO6qnCPsiQkaaZvZEBDLkgx4ygjVFP+6AAAABHNzaDo= ssh:";
    # Temporary root builder key
    temp-builder = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfniLMozPzqGcLeIDEwAsGcG7ndYhqaO6elSjB57HkH root@nixos-nvme";

    # Per-persona signing public keys. Populated when each persona's
    # private key is generated (Phase 1 — Stalwart provisioning). Until
    # then the entries are empty strings; consumers (allowed_signers
    # generator in lib/personas.nix) skip missing entries.
    #
    # Generation pattern per persona, run once per name in personas.nix:
    #   ssh-keygen -t ed25519 -C "<email>" -f sops/personas/<name>/id_ed25519 -N ""
    #   # then paste the .pub contents below.
    personas = {
      michael = "";
      thomas = "";
      daniel = "";
      rahul = "";
      juan = "";
    };
  };

  # Age/SOPS Public Keys (Recipients)
  age = {
    yubikey-primary = "age1yubikey1q2lhmqc0h6verf025hn62tkjkz25d760h54pdej7a55q4m2hszm8kwssfn0";
    yubikey-backup = "age1yubikey1qg379rzgajvstx6vhk2fsvc0eu9zyjjk7q24pd3pf5dq22xvlqew23e08l2";
    host-nvme = "age1tag1qg5qj4sam725ez6a53hkp5mnerf8m9dq4wy4nsfaraj3y5v6x8h0qexzvt7";
  };
}
