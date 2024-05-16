{
  lib,
  config,
  ...
}: let
  # A derivation with nix.lua, that contains data passed fron Nix to Lua
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
  lazyData = {lazy.root = config.public.pluginDir;};
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
      configure.packages = {
        lazy.start = [(config.public.lazyPath lazyData)];
      };
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
        configure.packages = {
          lazy.start = [(config.public.lazyPath {})];
        };
      };
    }
    // neovim;
}
