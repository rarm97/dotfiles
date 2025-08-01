return {
  "neovim/nvim-lspconfig",
  dependencies = {
    { "williamboman/mason.nvim", config = true },
    { "williamboman/mason-lspconfig.nvim", config = true },
    { "hrsh7th/cmp-nvim-lsp" },
  },
  config = function()
    local mason_lspconfig = require("mason-lspconfig")
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    mason_lspconfig.setup({
      ensure_installed = {
        "lua_ls",
        "pyright",
        "rust_analyzer",
        "ts_ls",
        "jsonls",
        "clangd", 
      },
      automatic_installation = true, -- v2+ flag
    })

    -- Manual custom config for Lua only!
    require("lspconfig").lua_ls.setup({
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
    -- All other servers will be set up automatically by mason-lspconfig.
  end,
}
