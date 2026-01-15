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
                "lua_ls",
                "pyright",
                "rust_analyzer",
                "ts_ls",
                "jsonls",
                "clangd",
            },
            automatic_installation = true,
        })
    -- Neovim 0.11 native LSP configuration
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

    vim.lsp.config("pyright", { capabilities = capabilities })
    vim.lsp.config("rust_analyzer", { capabilities = capabilities })
    vim.lsp.config("ts_ls", { capabilities = capabilities })
    vim.lsp.config("jsonls", { capabilities = capabilities })
    vim.lsp.config("clangd", { capabilities = capabilities })

    vim.lsp.enable({
      "lua_ls",
      "pyright",
      "rust_analyzer",
      "ts_ls",
      "jsonls",
      "clangd",
    })
    end,
}
