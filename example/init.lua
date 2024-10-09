-- The `lazy.from-nix` module contains the attribute set in `passedToLua`
local from_nix = require("lazy.from-nix")

require("lazy").setup({
  { "nvim-lua/plenary.nvim", lazy = true },
  {
    -- Install Telescope from GitHub
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    opts = {},
  },
  {
    -- Install Treesitter with parsers from Nix (see `flake.nix`)
    name = "nvim-treesitter",
    dir = from_nix.plugins.treesitter,
    -- You could even move `opts` to Nix and use `from_nix` here
    opts = {
      highlight = {
        enable = true,
      },
    },
    main = "nvim-treesitter.configs",
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      lspconfig.lua_ls.setup({
        -- Specify the LSP binary from Nix
        cmd = { from_nix.lsp.lua_ls },
      })
      lspconfig.nil_ls.setup({
        cmd = { from_nix.lsp.nil_ls },
      })
    end,
  },
  { "folke/lazydev.nvim", opts = {}, ft = "lua" },
  {
    "nvimtools/none-ls.nvim",
    opts = function()
      local null_ls = require("null-ls")
      return {
        sources = {
          null_ls.builtins.formatting.alejandra.with({
            command = from_nix.lsp.alejandra,
          }),
        },
      }
    end,
    event = "BufEnter",
  },
  -- `url` for non-GitHub repos
  { url = "https://git.sr.ht/~hedy/outline.nvim", opts = {} },
  {
    name = "markdown-preview",
    -- For plugins that need external dependencies (like NodeJS, Python), try
    -- the version from nixpkgs
    dir = from_nix.plugins.markdown_preview,
    ft = { "markdown" },
  },
  -- Semantic versioning works
  { "folke/which-key.nvim", opts = {}, version = "^2" },
  -- Use plugins that use `lazy.lua`
  { "folke/noice.nvim", opts = {} },
})
