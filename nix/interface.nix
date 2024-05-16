{
  lib,
  config,
  ...
}: let
  t = lib.types;
in {
  config.deps = {nixpkgs, ...}: {
    inherit (nixpkgs) neovim-unwrapped;
  };

  options = {
    neovimConfigFile = lib.mkOption {
      type = t.oneOf [t.package t.path t.str];
      description = "The path to the Neovim entry config file";
      example = lib.literalExpression "./init.lua";
    };

    neovim = lib.mkOption {
      type = t.package;
      description = "The Neovim derivation that will be wrapped";
      default = config.deps.neovim-unwrapped;
    };

    passedToLua = lib.mkOption {
      type = t.attrs;
      description = "Any value that should be available in `nix.lua`";
      default = {};
    };
  };
}
