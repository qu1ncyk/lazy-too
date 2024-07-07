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
      type = t.oneOf [t.path t.package t.str];
      description = "The path to the Neovim entry config file";
      example = lib.literalExpression "./init.lua";
      default = config.configRoot + "/init.lua";
    };

    configRoot = lib.mkOption {
      type = t.nullOr (t.oneOf [t.path t.package]);
      description = ''
        The path to the root directory of your Neovim config
        (that contains directories like `lua`)
      '';
      example = lib.literalExpression "./.";
      default = null;
    };

    neovim = lib.mkOption {
      type = t.package;
      description = "The Neovim derivation that will be wrapped";
      default = config.deps.neovim-unwrapped;
    };

    passedToLua = lib.mkOption {
      type = t.attrs;
      description = "Any value that should be available in `from-nix.lua`";
      default = {};
    };
  };
}
