-- LSP: language intelligence (completions, diagnostics, go-to-definition, etc.).
-- Uses Neovim 0.11+ native vim.lsp.config API.
-- Mason auto-installs language servers; cmp-nvim-lsp advertises completion
-- capabilities so servers send richer results.
return {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
        -- mason-org, not williamboman: both repos moved there and the old paths
        -- are now 301 redirects. Git follows them, so this is future-proofing
        -- rather than a fix — run :Lazy sync once after this change so lazy
        -- rewrites the two origins.
        { "mason-org/mason.nvim", config = true },
        { "mason-org/mason-lspconfig.nvim" },
        { "hrsh7th/cmp-nvim-lsp" },
    },

    keys = {
        { "<leader>ld", vim.diagnostic.open_float, desc = "Line diagnostics" },
        { "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, desc = "Prev diagnostic" },
        { "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, desc = "Next diagnostic" },

        { "<leader>rn", vim.lsp.buf.rename, desc = "Rename symbol" },
        { "<leader>ca", vim.lsp.buf.code_action, desc = "Code action", mode = { "n", "v" } },
        { "gd", vim.lsp.buf.definition, desc = "Go to definition" },
        { "gD", vim.lsp.buf.type_definition, desc = "Go to type definition" },
        { "gi", vim.lsp.buf.implementation, desc = "Go to implementation" },
        { "gr", vim.lsp.buf.references, desc = "References" },
        -- No "K" here on purpose. Neovim 0.11 already maps K to hover, but
        -- buffer-locally and only `if maparg('K', 'n') == ''` — so declaring K
        -- in this table created a GLOBAL mapping that both defeated that guard
        -- and shadowed keywordprg (:Man) in every buffer without an LSP client.
        -- Dropping it restores :Man outside LSP buffers and lets 0.11 install
        -- (and clean up) its own hover map on attach and detach.
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
                "yamlls",
                "dockerls",
                "bashls",
            },
        })

        -- lua_ls: lazydev.nvim handles workspace library and vim globals,
        -- so we only need root markers and checkThirdParty here
        vim.lsp.config.lua_ls = {
            capabilities = capabilities,
            root_markers = { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml", ".git" },
            settings = {
                Lua = {
                    workspace = { checkThirdParty = false },
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
                    -- checkOnSave is a plain boolean now; the command moved to
                    -- its own `check` table. Passing the old map form makes
                    -- rust-analyzer reject the whole key as an invalid config
                    -- value, so clippy silently never runs on save.
                    checkOnSave = true,
                    check = { command = "clippy" },
                },
            },
        }

        vim.lsp.config.ts_ls = { capabilities = capabilities }
        vim.lsp.config.jsonls = { capabilities = capabilities }
        vim.lsp.config.clangd = { capabilities = capabilities }
        vim.lsp.config.gopls = { capabilities = capabilities }

        -- yamlls: schema validation for docker-compose, k8s, CI configs, etc.
        vim.lsp.config.yamlls = {
            capabilities = capabilities,
            settings = {
                yaml = {
                    schemaStore = { enable = true },
                },
            },
        }

        vim.lsp.config.dockerls = { capabilities = capabilities }
        vim.lsp.config.bashls = { capabilities = capabilities }

        vim.lsp.enable({
            "lua_ls",
            "pyright",
            "rust_analyzer",
            "ts_ls",
            "jsonls",
            "clangd",
            "gopls",
            "yamlls",
            "dockerls",
            "bashls",
        })
    end,
}
