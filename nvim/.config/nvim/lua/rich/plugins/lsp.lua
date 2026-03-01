-- LSP: language intelligence (completions, diagnostics, go-to-definition, etc.).
-- Uses Neovim 0.11+ native vim.lsp.config API.
-- Mason auto-installs language servers; cmp-nvim-lsp advertises completion
-- capabilities so servers send richer results.
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
        { "<leader>ca", vim.lsp.buf.code_action, desc = "Code action", mode = { "n", "v" } },
        { "gd", vim.lsp.buf.definition, desc = "Go to definition" },
        { "gD", vim.lsp.buf.type_definition, desc = "Go to type definition" },
        { "gi", vim.lsp.buf.implementation, desc = "Go to implementation" },
        { "gr", vim.lsp.buf.references, desc = "References" },
        { "K", vim.lsp.buf.hover, desc = "Hover" },
        { "<C-k>", vim.lsp.buf.signature_help, desc = "Signature help", mode = "i" },
        { "<leader>lq", vim.diagnostic.setqflist, desc = "Diagnostics to quickfix" },
    },

    config = function()
        local capabilities = require("cmp_nvim_lsp").default_capabilities()

        -- Mason auto-installs these servers on first run
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

        -- lua_ls: recognise vim global, index nvim runtime for completion
        vim.lsp.config.lua_ls = {
            capabilities = capabilities,
            root_markers = { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml", ".git" },
            settings = {
                Lua = {
                    diagnostics = { globals = { "vim" } },
                    runtime = { version = "LuaJIT" },
                    workspace = {
                        library = { vim.env.VIMRUNTIME },
                        checkThirdParty = false,
                    },
                },
            },
        }

        vim.lsp.config.pyright = { capabilities = capabilities }

        -- rust-analyzer: use the rustup-managed binary (not mason's),
        -- enable all cargo features, run clippy on save
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
