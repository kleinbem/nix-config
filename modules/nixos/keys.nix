{
  # Cachix Public Keys
  cachix = {
    nix-community = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
    cosmic = "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=";
    # kleinbem = "kleinbem.cachix.org-1:ADD_YOUR_PUBLIC_KEY_HERE";
  };

  # SSH Public Keys
  ssh = {
    yubikey = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPbkLwSKFiip5e/0j9aHzIDr+4srK7s9C/aLbNOl7xJQAAAABHNzaDo= yubikey-resident";
  };

  # Age/SOPS Public Keys (Recipients)
  age = {
    yubikey-primary = "age1yubikey1q2lhmqc0h6verf025hn62tkjkz25d760h54pdej7a55q4m2hszm8kwssfn0";
    yubikey-backup = "age1yubikey1qg379rzgajvstx6vhk2fsvc0eu9zyjjk7q24pd3pf5dq22xvlqew23e08l2";
    host-nvme = "age1tag1qg5qj4sam725ez6a53hkp5mnerf8m9dq4wy4nsfaraj3y5v6x8h0qexzvt7";
  };
}
