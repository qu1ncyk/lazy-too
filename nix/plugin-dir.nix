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
in {
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      nix-prefetch-git
      nurl
      runCommand
      symlinkJoin
      writeShellScript
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
  public.pluginDir = combineDrvs (map fetchPlugin config.lock.content.plugins);

  lock.fields = {
    plugins.script = config.deps.writeShellScript "prefetch plugins" ''
      export PATH=${config.deps.nix-prefetch-git}/bin:$PATH
      export PATH=${config.deps.nurl}/bin:$PATH
      export LAZY_TOO=lock
      ${config.public.neovim-prefetch}/bin/nvim -l '${config.neovimConfigFile}'
    '';
  };
}
