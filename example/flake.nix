{
  description = "lazy-too example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    lazy-too.url = "github:qu1ncyk/lazy-too";
    neorg-overlay.url = "github:nvim-neorg/nixpkgs-neorg-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    lazy-too,
    neorg-overlay,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.extend neorg-overlay.overlays.default;
      in {
        packages = rec {
          default = lazy-too.packages.${system}.buildNeovim {
            # Specify a config root or init file (or both)
            configRoot = ./.;
            # neovimConfigFile = ./init.lua;

            # Tell Dream2Nix that this is the root dir
            # https://nix-community.github.io/dream2nix/reference/builtins-derivation/#paths
            paths = {
              projectRoot = ./.;
              projectRootFile = "flake.nix";
              package = ./.;
            };

            neovim = pkgs.neovim-unwrapped;

            passedToLua = {
              plugins = {
                treesitter = pkgs.symlinkJoin {
                  name = "Treesitter and parsers";
                  paths = with pkgs.vimPlugins.nvim-treesitter-parsers; [
                    pkgs.vimPlugins.nvim-treesitter
                    vimdoc
                    nix
                    lua
                    norg
                  ];
                };
                markdown_preview = pkgs.vimPlugins.markdown-preview-nvim;
              };

              lsp = {
                lua_ls = pkgs.lua-language-server + "/bin/lua-language-server";
                nil_ls = pkgs.nil + "/bin/nil";
                alejandra = pkgs.alejandra + "/bin/alejandra";
              };
            };
          };
          inherit (default) lock;
        };
      }
    );
}
