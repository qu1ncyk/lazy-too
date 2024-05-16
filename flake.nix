{
  description = "lazy.nvim with Nix integration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dream2nix.url = "github:nix-community/dream2nix";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    dream2nix,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = rec {
          buildNeovim = config: (dream2nix.lib.evalModules {
            packageSets.nixpkgs = pkgs;
            modules = [
              config
              d2nModule
            ];
          });
          d2nModule = ./nix;
        };
      }
    );
}
