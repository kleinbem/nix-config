let
  lib = import <nixpkgs/lib>;
  module = {
    options = {
      containers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.config = lib.mkOption {
              type = lib.types.submodule {
                options.system.stateVersion = lib.mkOption {
                  type = lib.types.str;
                  default = "26.11";
                };
                options.nixpkgs.allowUnfree = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
            };
          }
        );
      };
    };
    config = lib.mkMerge [
      {
        containers.ollama.config = lib.mkMerge [
          { system.stateVersion = "25.11"; }
        ];
      }
      {
        containers.ollama.config.nixpkgs.allowUnfree = true;
      }
    ];
  };
  eval = lib.evalModules { modules = [ module ]; };
in
eval.config.containers.ollama.config.system.stateVersion
