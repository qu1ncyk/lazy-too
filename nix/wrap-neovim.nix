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
in {
  imports = [
    ./plugin-dir.nix
    ./interface.nix
  ];

  deps = {nixpkgs, ...}: {inherit (nixpkgs) wrapNeovim writeTextFile;};

  public = let
    # The wrapped Neovim
    neovim = config.deps.wrapNeovim config.neovim {
      extraMakeWrapperArgs = "--add-flags -u --add-flags '${config.neovimConfigFile}'";
      configure.packages =
        {lazy.start = [lazyPathWithHelptags.drv];}
        // configRootPlugin;
    };

    configRootPlugin = lib.attrsets.optionalAttrs (config.configRoot != null) {
      lua.start = [(toDerivation config.configRoot)];
    };

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
      neovim-prefetch = config.deps.wrapNeovim config.neovim {
        configure.packages =
          {
            lazy.start = [
              (config.public.lazyPath {
                lazy = {root = emptyDerivation;} // configRootPathData;
              })
            ];
          }
          // configRootPlugin;
      };
    }
    // neovim;
}
