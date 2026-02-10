{
  lib,
  config,
  ...
}: let
  fetchRepo = {
    args,
    fetcher,
  }:
    config.deps.fetchers.${fetcher} args;

  linkDrvScript = {
    drv,
    name,
  }: "ln -s ${drv} $out/${lib.strings.escapeShellArg name}\n";

  # Put multiple derivations in directories with given names.
  combineDrvs = drvs:
    config.deps.runCommand "combine drvs" {} (
      "mkdir $out\n"
      + lib.strings.concatMapStrings linkDrvScript drvs
    );

  builtPluginDirs =
    lib.attrsets.mapAttrsToList
    (name: p:
      config.public.generateHelptags {
        inherit name;
        drv = fetchRepo p;
      })
    config.lock.content.plugins.git;

  fetchRock = attrs:
    if builtins.hasAttr "src_rock" attrs
    then fetchSrcRock attrs
    else fetchRockspec attrs;

  fetchSrcRock = attrs: let
    name = builtins.baseNameOf attrs.src_rock;
  in
    config.deps.runCommand name {
      srcRock = config.deps.fetchurl {
        url = attrs.src_rock;
        inherit (attrs) hash;
      };
      filename = name;
    } ''
      mkdir $out
      ln -s "$srcRock" "$out/$filename"
    '';

  # Fetch a `.rockspec` and pack it as a `.src.rock`
  fetchRockspec = attrs: let
    rockspecFilename = builtins.baseNameOf attrs.rockspec;
    srcRockFilename = builtins.replaceStrings [".rockspec"] [".src.rock"] rockspecFilename;
  in
    config.deps.runCommand "${srcRockFilename} from rockspec" {
      inherit rockspecFilename srcRockFilename;
      rockspec = config.deps.fetchurl {
        url = attrs.rockspec;
        inherit (attrs) hash;
      };
      source = fetchRepo attrs.src;
      buildInputs = [config.deps.luarocks];
    } ''
      mkdir $out
      # LuaRocks needs the files in the rock zip to have writable permissions
      cp -rL "$source" source
      cp "$rockspec" $rockspecFilename
      chmod -R +w *
      zip -r "$out/$srcRockFilename" "$rockspecFilename" source
    '';

  # Create a [rocks server](https://github.com/luarocks/luarocks/wiki/make-manifest)
  # directory from an attribute set of dependencies
  rocksServer = rocks:
    config.deps.symlinkJoin {
      name = "rocks server";
      paths =
        lib.attrsets.mapAttrsToList
        (_: fetchRock)
        rocks;
      buildInputs = [config.deps.luarocks];
      postBuild = "luarocks-admin make-manifest $out";
    };

  rocksServers = let
    serverList =
      lib.attrsets.mapAttrsToList (name: dependent: {
        inherit name;
        drv = rocksServer dependent;
      })
      config.lock.content.plugins.rocks;
  in
    combineDrvs serverList;

  rockRoot =
    config.deps.runCommand "rock root" {
      inherit rocksServers rootPluginDir;
      buildInputs = [config.deps.luarocks];
    } ''
      mkdir $out

      for plugin in $(ls "$rootPluginDir"); do
        plugindir="$rootPluginDir/$plugin"
        if [ -n "$(echo -n "$plugindir"/*.rockspec)" ]; then
          for dependency in "$rocksServers/$plugin"/*.src.rock; do
            luarocks install "$dependency" --tree "$out/$plugin" --deps-mode none --force-fast
          done
          # LuaRocks needs source of the plugin rock to have writable permissions
          cp -rL "$plugindir" plugin
          chmod -R +w plugin
          pushd plugin
          luarocks make --tree "$out/$plugin" --deps-mode none --force-fast
          popd
          rm -r plugin
        fi
      done
    '';

  # The directory with all plugins
  rootPluginDir = combineDrvs builtPluginDirs;
in {
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      nix-prefetch-git
      nurl
      runCommand
      symlinkJoin
      writeShellApplication
      stdenvNoCC
      jq
      fetchurl
      ;
    inherit (nixpkgs.lua51Packages) luarocks;
    # All possible outputs of `nurl` (minus builtins.fetchGit)
    fetchers = {
      inherit
        (nixpkgs)
        fetchCrate
        fetchFromBitbucket
        fetchFromGitea
        fetchFromGitHub
        fetchFromGitiles
        fetchFromGitLab
        fetchFromRepoOrCz
        fetchFromSourcehut
        fetchgit
        fetchHex
        fetchhg
        fetchPypi
        fetchsvn
        ;
    };
  };

  public.pluginDir = rootPluginDir;
  public.rockRoot = rockRoot;

  # Generate the Vim helptags for a given plugin.
  public.generateHelptags = {
    drv,
    name,
  }: {
    inherit name;
    drv = config.deps.stdenvNoCC.mkDerivation {
      name = "${name} with helptags";
      src = drv;
      buildInputs = [config.neovim];
      buildPhase = ''
        if [ -d doc ]; then
          nvim --headless -i NONE -u NONE -c 'helptags doc|q'
        fi
      '';
      installPhase = "cp . $out -r";
      # The default `fixupPhase` moves the `doc` dir into `share`
      dontFixup = true;
    };
  };

  lock.fields = {
    plugins.script = let
      prefetcher = config.deps.writeShellApplication {
        name = "prefetch-plugins";
        runtimeInputs = with config.deps; [
          nix-prefetch-git
          nurl
          luarocks
          jq
          config.public.neovim-prefetch
        ];
        checkPhase = false;

        text = ''
          export LAZY_TOO=lock
          nvim -l '${config.neovimConfigFile}'

          # Sort the keys to be more Git-friendly
          jq --sort-keys . $out > tmp
          mv tmp $out
        '';
      };
    in "${prefetcher}/bin/prefetch-plugins";
  };
}
