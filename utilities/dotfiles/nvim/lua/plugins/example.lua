-- Custom plugins and theme configuration
-- All LazyVim extras are managed in lazyvim.json
return {
  -- theme
  { "rose-pine/neovim", name = "rose-pine", priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "rose-pine",
    },
  },
  {
    "rose-pine/neovim",
    lazy = true,
    opts = {
      variant = "auto",
      dark_variant = "main",
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {
          keys = {
            { "gd", vim.lsp.buf.definition, desc = "Goto Definition" },
            { "gD", vim.lsp.buf.declaration, desc = "Goto Declaration" },
            { "gr", vim.lsp.buf.references, desc = "References" },
            { "gi", vim.lsp.buf.implementation, desc = "Goto Implementation" },
            { "K", vim.lsp.buf.hover, desc = "Hover" },
          },
        },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "sourcekit-lsp",
      },
    },
  },
}
