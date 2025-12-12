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

    vim.lsp.config("lua_ls", {
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

    -- Minimal configs for other servers (you can expand later)
    vim.lsp.config("ts_ls", { capabilities = capabilities })
    vim.lsp.config("jsonls", { capabilities = capabilities })
    vim.lsp.config("pyright", { capabilities = capabilities })
    vim.lsp.config("rust_analyzer", { capabilities = capabilities })
    vim.lsp.config("clangd", { capabilities = capabilities })

    -- Enable them
    vim.lsp.enable({
      "lua_ls",
      "ts_ls",
      "jsonls",
      "pyright",
      "rust_analyzer",
      "clangd",
    })
  end,
}
