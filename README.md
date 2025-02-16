# lazy-too

A fork of [lazy.nvim](https://github.com/folke/lazy.nvim) that provides support for Nix

## Installation

This guide assumes that you have a (system) configuration using flakes.
If you want to see an example configuration using lazy-too, take a look at the
[`example` directory](https://github.com/qu1ncyk/lazy-too/blob/main/example/flake.nix)
or [my personal configuration](https://github.com/qu1ncyk/nix-conf).

Add the following to your `flake.nix`:

```nix
{
  inputs = {
    lazy-too.url = "github:qu1ncyk/lazy-too";
  };

  outputs = {
    lazy-too,
    self,
  }: let
    system = "x86_64-linux";
  in {
    packages.${system} = rec {
      # nix run .#nvim
      nvim = lazy-too.packages.${system}.buildNeovim {
        configRoot = ./.;
        paths = {
          projectRoot = ./.;
          projectRootFile = "flake.nix";
          package = ./.;
        };
      };

      # nix run .#lock
      inherit (nvim) lock;
    };
  };
}
```

Now place your [lazy.nvim configuration](https://lazy.folke.io/installation)
in the same directory as `flake.nix`, but **remove the bootstrapping part**.

## Usage

When you add a new plugin to your config, run:

```sh
nix run .#lock
```

to generate a new lockfile.
This command prefetches all plugins to obtain their hashes and commit revisions.
The command

```sh
nix run .#nvim
```

builds the configuration using Nix and launches Neovim.
The resulting Neovim instance uses its own config and is independent from `~/.config/nvim`.

## Configuration

lazy-too can be configured from Nix through options given to `buildNeovim`.
See [`nix/interface.nix`](https://github.com/qu1ncyk/lazy-too/blob/main/nix/interface.nix) for details.

`passedToLua` accepts an attribute set with values that will be available in Lua via `require("lazy.from-nix")`.
This lets you use programs/plugins from nixpkgs in your config.
You can use this as a replacement for [mason.nvim](https://github.com/williamboman/mason.nvim).

`neovimConfigFile` and `configRoot` specify where the Neovim config is.
`neovimConfigFile` defaults to `<configRoot>/init.lua`.
`configRoot` is optional and only needed when your config consists of multiple Lua files.
If you are unsure, stick with `configRoot`, just like in the example above.

`neovim` specifies the Neovim derivation that will be wrapped so that it runs with the correct config.
By default, this is `neovim-unwrapped` from nixpkgs.

`paths` is used by [Dream2Nix](https://dream2nix.dev/reference/builtins-derivation/#pathslockfile),
which lazy-too uses under the hood.
It makes sure that the lockfile can be found during both locking and building.

### Outputs

`buildNeovim` outputs an attribute set with the following fields (among others):

- `neovim`: The resulting executable.
  (`neovim` is also merged with the parent attribute set so that you can use that as a derivation.)
- `lock` (aka `neovim.lock`): The script that updates the lockfile.

## lazy.nvim features that are currently broken

- `build` option in plugin spec and `build.lua`.
- Automatic helptags generation from markdown.
- Per-project `.lazy.lua` configuration.
- Commit changelog on plugin update.
- [Packspec](https://github.com/neovim/packspec).

## Compared to alternatives

- [lazy.nvim](https://github.com/folke/lazy.nvim) downloads plugins during runtime. lazy-too uses Nix for this.
- [NixVim](https://github.com/nix-community/nixvim) lets you manage your Neovim config (almost) entirely from Nix.
  From my experience, this works great for plugins that are supported,
  but is less ergonomic when a plugin is not supported or accepts a Lua function for its config.
- [nixCats](https://github.com/BirdeeHub/nixCats-nvim) has a similar mentality for using Nix for downloading and Lua for configuring.
  It uses `nixCats("attr.path")` where lazy-too uses `require("lazy.from-nix").attr.path`.
  Unlike lazy-too, it's designed not to be bound to a specific Lua plugin manager.
  (Disclaimer: I haven't personally used this and only found it after I started working on lazy-too.)

## Thanks

- [lazy.nvim](https://github.com/folke/lazy.nvim): Original plugin manager.
- [Dream2Nix](https://github.com/nix-community/dream2nix): Lockfile mechanism.
- [nurl](https://github.com/nix-community/nurl): Easy prefetching.
