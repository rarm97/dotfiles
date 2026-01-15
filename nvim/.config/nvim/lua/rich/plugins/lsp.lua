return {
  "neovim/nvim-lspconfig",
  dependencies = {
    { "williamboman/mason.nvim", config = true },
    { "williamboman/mason-lspconfig.nvim", config = true },
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
    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    mason_lspconfig.setup({
      ensure_installed = {
        "lua_ls",
        "pyright",
        "rust_analyzer",
        "tsserver",
        "jsonls",
        "clangd",
      },
      automatic_installation = true,
    })

    mason_lspconfig.setup_handlers({
      -- Default handler for all installed servers
      function(server_name)
        lspconfig[server_name].setup({
          capabilities = capabilities,
        })
      end,

      -- Server-specific overrides
      ["lua_ls"] = function()
        lspconfig.lua_ls.setup({
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
        })
      end,
    })
  end,
}
