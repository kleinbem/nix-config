rec {
  # Cachix Public Keys
  cachix = {
    nix-community = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
    devenv = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    anduril = "anduril.cachix.org-1:0KJgGiAgDtCE9Pl0wvvyALRJlPhQMLRMMt+43JExFlY=";
    # What kleinbem/nixpkgs-review-gha builds for open nixpkgs PRs (public).
    kleinbem-nixpkgs-review = "kleinbem-nixpkgs-review.cachix.org-1:JVJSauhW05AExFFqnrWtsfg4hxNieKFFq7tntGb63q4=";
  };

  # Other Binary Cache Public Keys (non-cachix)
  binaryCache = {
    # Official CUDA nixpkgs cache (https://wiki.nixos.org/wiki/CUDA). Public.
    nixos-cuda = "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=";
    # Fleet build-signing key (secret in nix/shared-signing.yaml, core.nix).
    # Every host signs local builds with it, so `nix copy` between hosts
    # verifies without going through CI and Attic.
    kleinbem-fleet-build = "kleinbem-fleet-build-1:2WtnzmBEU1YqC25CzcVOXs/j926Qp9yT5REoNkEqnbw=";
  };

  # SSH Public Keys
  ssh = {
    yubikey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFLSRkt7uoF1c2iWpwt7mJi2krEtmpdUD4wLUm0XTn5JbGIBce+avhSqY02YRe3dpRVqo7KGE8upe11xI8IcEjk= PIV AUTH pubkey";
    # FIDO2 resident key (id_ed25519_sk) — works without PKCS11 and is offered by ssh-agent automatically
    fido2 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPbkLwSKFiip5e/0j9aHzIDr+4srK7s9C/aLbNOl7xJQAAAABHNzaDo=";
    # FIDO2 backup resident key
    fido2-backup = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINYunZXaiafJQO6qnCPsiQkaaZvZEBDLkgx4ygjVFP+6AAAABHNzaDo= ssh:";
    # No-touch SK key for git/jj commit signing
    # (~/.ssh/id_ed25519_sk_rk_GitHubNoTouchV2). Generate with
    # -O no-touch-required, or every sign still asks for a touch.
    fido2-notouch = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBZ4U3wGwDb7DDfBsT4wH208lzSiQRhFb+CN3tJc+HIHAAAAE3NzaDpHaXRIdWJOb1RvdWNoVjI= ssh:GitHubNoTouchV2";

    # Dedicated SSH key for Huawei MatePad Pro (Termux)
    tablet-termux = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGoNas82bJQ8pUEz5Ks22UrUwvAposKYXH8fp7yY1DAy martin-tablet-termux";

    # Dedicated SSH key for Samsung Galaxy XCover 6 Pro (Termux)
    phone-termux = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJUdmrp/ONOwEEzJFtojToFYXOQSDBiOCcr608xqbF42 martin-phone--termux";

    # Plain key for nixos-nvme's unattended Caddy CA pull (caddy-ca-refresh.nix);
    # a timer can't answer a touch. `restrict`+`command=` limit it to reading
    # one public cert.
    caddy-ca-refresh = ''command="cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDfu0f4YfeLsHx9CO4BZtgBpx1YJ8Qdv7LwM57zyBVP/ refresh-caddy-ca@nixos-nvme'';

    # Per-persona signing keys; lib/personas.nix skips missing entries.
    # New persona:
    #   ssh-keygen -t ed25519 -C "<email>" -f sops/personas/<name>/id_ed25519 -N ""
    #   # then paste the .pub contents below.
    personas = {
      michael-gruber = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVfwD0GCXVUnFMOLDrCaqLNnhQCYNnG+vkEDXdUAerE michael.gruber@kleinbem.dev";
      thomas-schmidt = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIxNAzon0u0FduqmXLtBSAOwzfmQ5OU3fNKap0oTLcN thomas.schmidt@kleinbem.dev";
      daniel-meier = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJSXFMGWBPlN80vuOiJrMd+safHcKCjcHeDU8iCYHchL daniel.meier@kleinbem.dev";
      rahul-kumar = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIArxoaUKMOS99lj9nWWgQ5zA9SBcowCWUi63HyPEE0XO rahul.kumar@kleinbem.dev";
      juan-gonzalez = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKbZOI7NAi8Q2AVucHIJEFNPSi5/rxKtnyZvN2BjNIK9 juan.gonzalez@kleinbem.dev";
    };
  };

  # Age/SOPS Public Keys (Recipients)
  age = {
    yubikey-primary = "age1yubikey1q2lhmqc0h6verf025hn62tkjkz25d760h54pdej7a55q4m2hszm8kwssfn0";
    yubikey-backup = "age1yubikey1qg379rzgajvstx6vhk2fsvc0eu9zyjjk7q24pd3pf5dq22xvlqew23e08l2";
    host-nvme = "age1tag1qg5qj4sam725ez6a53hkp5mnerf8m9dq4wy4nsfaraj3y5v6x8h0qexzvt7";
  };

  # Initrd (remote-unlock) SSH host keys, port 2222. Private halves live only
  # on each host in /nix/persist/secrets (my.hostSecrets); make them with
  # `just access::host-keygen <host>`.
  initrdHostKeys = {
    nixos-nvme = {
      ip = "10.0.0.5";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILCPyhYle/z0elgfzurxQgh4UHZbbw6xxeAlYRCS8o0i";
    };
    core-pi = {
      ip = "10.0.0.22";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICHxR4gtUWFxs/3Cpb8mzp7GiELddhoyJufCo9bGRIO1";
    };
    hass-pi = {
      ip = "10.0.0.21";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoYz5JmoKxqyDuu32bAQwpLTnDHpu47i5/kinYnyOc8";
    };
    mac-mini = {
      ip = "10.0.0.16";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHfwhPmhv2GBuMOllaoTNSeiQLTqizKpQ2HlwYH2fGCx";
    };
    nasbook = {
      ip = "10.0.0.30";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIED1MCkRGoF5mSh/5UUJHLkzysk1JA1EkslAwQlczYv+";
    };
    orin-nano = {
      ip = "10.0.0.15";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH8AzB6jowZtkTZoz3Zq58PTb38XdXLW/6qi2rxFHxQy";
    };
  };

  # Public caches the fleet substitutes from. core.nix trusts them, and
  # Attic skips paths signed by any of them (the atticd upstream filter on
  # core-pi and push-cache's local filter), so it holds only what no
  # public cache has. Add a new public cache here, not in core.nix.
  upstreamCaches = [
    "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg="
    cachix.nix-community
    cachix.devenv
    cachix.anduril
    binaryCache.nixos-cuda
  ];
  # Just the key names, which is what Attic's filter matches on.
  upstreamCacheKeyNames = map (k: builtins.head (builtins.split ":" k)) upstreamCaches;
}
