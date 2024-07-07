{
  lib,
  config,
  ...
}: let
  fetchPlugin = {
    args,
    fetcher,
    name,
  }: {
    drv = config.deps.fetchers.${fetcher} args;
    inherit name;
  };

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

  attrsToList = lib.attrsets.mapAttrsToList (name: val: {inherit name;} // val);
in {
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      nix-prefetch-git
      nurl
      runCommand
      symlinkJoin
      writeShellScript
      stdenvNoCC
      jq
      ;
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

  # The directory with all plugins
  public.pluginDir = combineDrvs (map
    (p: config.public.generateHelptags (fetchPlugin p))
    (attrsToList config.lock.content.plugins));

  # Generate the Vim helptags for a given plugin.
  public.generateHelptags = {
    drv,
    name,
  }: {
    inherit name;
    drv = config.deps.stdenvNoCC.mkDerivation {
      name = "${name} with helptags";
      src = drv;
      buildInputs = [config.public.neovim-prefetch];
      buildPhase = ''
        if [ -d doc ]; then
          nvim --clean -c 'helptags doc' -c q
        fi
      '';
      installPhase = "cp . $out -r";
      # The default `fixupPhase` moves the `doc` dir into `share`
      dontFixup = true;
    };
  };

  lock.fields = {
    plugins.script = config.deps.writeShellScript "prefetch plugins" ''
      export PATH=${config.deps.nix-prefetch-git}/bin:$PATH
      export PATH=${config.deps.nurl}/bin:$PATH
      export LAZY_TOO=lock
      ${config.public.neovim-prefetch}/bin/nvim -l '${config.neovimConfigFile}'

      # Sort the keys to be more Git-friendly
      ${config.deps.jq}/bin/jq --sort-keys . $out > tmp
      mv tmp $out
    '';
  };
}
