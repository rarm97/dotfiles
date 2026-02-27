return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" }, 
  dependencies = {
    { "williamboman/mason.nvim", config = true },
    { "williamboman/mason-lspconfig.nvim" },
    { "hrsh7th/cmp-nvim-lsp" },
  },

  keys = {
    { "<leader>ld", vim.diagnostic.open_float, desc = "Line diagnostics" },
    { "[d", vim.diagnostic.goto_prev, desc = "Prev diagnostic" },
    { "]d", vim.diagnostic.goto_next, desc = "Next diagnostic" },

    { "<leader>rn", vim.lsp.buf.rename, desc = "Rename symbol" },
    { "gd", vim.lsp.buf.definition, desc = "Go to definition" },
    { "gi", vim.lsp.buf.implementation, desc = "Go to implementation" },
    { "gr", vim.lsp.buf.references, desc = "References" },
    { "K", vim.lsp.buf.hover, desc = "Hover" },
  },    

  config = function()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    require("mason-lspconfig").setup({
      ensure_installed = {
        "gopls",
        "lua_ls",
        "pyright",
        "ts_ls",
        "jsonls",
        "clangd",
      },
      automatic_installation = true,
    })

    -- Neovim 0.11+ native LSP configuration (consistent style)

    vim.lsp.config.lua_ls = {
      capabilities = capabilities,
      settings = {
        Lua = {
          diagnostics = { globals = { "vim" } },
          workspace = {
            library = vim.api.nvim_get_runtime_file("", true),
            checkThirdParty = false,
          },
        },
      },
    }

    vim.lsp.config.pyright = { capabilities = capabilities }

    -- Prefer rustup-managed rust-analyzer (on PATH)
    vim.lsp.config.rust_analyzer = {
      cmd = { "rust-analyzer" },
      filetypes = { "rust" },
      root_markers = { "Cargo.toml", "rust-project.json", ".git" },
      capabilities = capabilities,
      settings = {
        ["rust-analyzer"] = {
          cargo = { allFeatures = true },
          checkOnSave = { command = "clippy" },
        },
      },
    }

    vim.lsp.config.ts_ls = { capabilities = capabilities }
    vim.lsp.config.jsonls = { capabilities = capabilities }
    vim.lsp.config.clangd = { capabilities = capabilities }
    vim.lsp.config.gopls = { capabilities = capabilities }
    vim.lsp.enable({
      "lua_ls",
      "pyright",
      "rust_analyzer",
      "ts_ls",
      "jsonls",
      "clangd",
      "gopls",
    })
  end,
}
