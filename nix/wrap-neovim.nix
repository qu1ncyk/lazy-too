{
  lib,
  config,
  ...
}: let
  # A derivation with from-nix.lua, that contains data passed fron Nix to Lua
  passToLua = data: let
    finalData =
      lib.attrsets.recursiveUpdate
      config.passedToLua
      data;
  in
    config.deps.writeTextFile {
      name = "pass to Lua";
      text = "return " + lib.generators.toLua {} finalData;
      destination = "/lua/lazy/from-nix.lua";
    };

  # Runtime data for from-nix.lua
  lazyData = {
    lazy = {root = config.public.pluginDir;} // configRootPathData;
  };

  # The entry in from-nix.lua that contains the config root directory
  configRootPathData = lib.attrsets.optionalAttrs (config.configRoot != null) {
    config_root = "${config.configRoot}";
  };

  wrapNeovim = {
    neovim,
    args ? [],
    packPath ? [],
  }:
    if packPath != []
    then
      wrapNeovim {
        inherit neovim;
        args =
          builtins.concatMap
          (x: ["--cmd" "'set rtp^='${lib.strings.escapeShellArg x}"])
          packPath
          ++ args;
      }
    else let
      flatArgs = lib.strings.concatStringsSep " " args;
    in
      config.deps.writeShellScriptBin "nvim" ''
        exec ${neovim}/bin/nvim ${flatArgs} $@
      '';
in {
  imports = [
    ./plugin-dir.nix
    ./interface.nix
  ];

  deps = {nixpkgs, ...}: {inherit (nixpkgs) writeTextFile writeShellScriptBin;};

  public = let
    # The wrapped Neovim
    neovim = wrapNeovim {
      inherit (config) neovim;
      args = ["-u" "${config.neovimConfigFile}"];
      packPath = [lazyPathWithHelptags.drv] ++ configRootList;
    };

    configRootList = lib.lists.optional (config.configRoot != null) (toDerivation config.configRoot);

    emptyDerivation = config.deps.symlinkJoin {
      name = "empty";
      paths = [];
    };

    # A custom implementation of `lib.attrsets.toDerivation` that doesn't use
    # `builtins.storePath`. `storePath` is forbidden in flakes.
    toDerivation = path:
      config.deps.symlinkJoin {
        name = "toDerivation";
        paths = [path];
      };

    lazyPathWithHelptags = config.public.generateHelptags {
      drv = config.public.lazyPath lazyData;
      name = "lazy-too";
    };
  in
    {
      # Lazy root dir + from-nix.lua
      lazyPath = data:
        config.deps.symlinkJoin {
          name = "lazy path";
          paths = [../. (passToLua data)];
        };

      inherit neovim;

      # The wrapped Neovim that is used when prefetching the plugins
      neovim-prefetch = wrapNeovim {
        inherit (config) neovim;
        packPath =
          [
            (config.public.lazyPath {
              lazy = {root = emptyDerivation;} // configRootPathData;
            })
          ]
          ++ configRootList;
      };
    }
    // neovim;
}
