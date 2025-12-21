_:

{
  programs = {
    bash.enable = true;

    starship = {
      enable = true;
      settings = {
        add_newline = false;
      };
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "kleinbem";
          email = "martin.kleinberger@gmail.com";
        };
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
