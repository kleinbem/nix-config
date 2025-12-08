(final: prev: {
  # TEMP FIX 1: cosmic-edit hash mismatch
  cosmic-edit = prev.cosmic-edit.overrideAttrs (old: {
    src = old.src.override {
      # "got" from the cosmic-edit error
      hash = "sha256-GN1Zts+v3ARcrkN+ZkMUSGNOAlIhXSYWRtWAyqUfUrY=";
    };
  });

  # TEMP FIX 2: cosmic-greeter hash mismatch
  cosmic-greeter = prev.cosmic-greeter.overrideAttrs (old: {
    src = old.src.override {
      # "got" from the greeter/vendor error
      hash = "sha256-ERytoauws6FDJNXItflOE2MwjxwariiO8RXU1x1chkE=";
    };
  });

  # TEMP FIX 3: xdg-desktop-portal-cosmic vendor hash mismatch
  xdg-desktop-portal-cosmic =
    prev.xdg-desktop-portal-cosmic.overrideAttrs (old: {
      src = old.src.override {
        # same "got" hash as the failing ...-source.drv
        hash = "sha256-ERytoauws6FDJNXItflOE2MwjxwariiO8RXU1x1chkE=";
      };
    });
})