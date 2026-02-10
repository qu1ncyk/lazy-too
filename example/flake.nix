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
        # The Neorg overlay adds the Neorg Neovim plugin and Norg treesitter parser.
        # If you don't use Neorg, you can remove the overlay.
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
                    # nvim-treesitter normally copies queries from `runtime/queries`
                    # to `~/.local/share/nvim/site/queries`
                    # https://github.com/nvim-treesitter/nvim-treesitter/blob/4967fa48b0fe7a7f92cee546c76bb4bb61bb14d5/lua/nvim-treesitter/install.lua#L412
                    (pkgs.vimPlugins.nvim-treesitter.overrideAttrs {
                      fixupPhase = ''
                        # `runtime` is not actually part of the runtimepath,
                        # but the plugin root dir is
                        mv $out/runtime/queries $out
                        rm runtime -r
                      '';
                    })
                    vim
                    vimdoc
                    nix
                    lua
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
