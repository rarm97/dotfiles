-- Auto-formatting on save. Falls back to LSP formatting if no dedicated
-- formatter is configured for the filetype. Manual format: <leader>cf.
-- Formatter defaults (indent width, etc.) come from global config files
-- in ~/  (.prettierrc, .stylua.toml, .clang-format); project-level
-- configs override these automatically.
return {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
        {
            "<leader>cf",
            function()
                require("conform").format({ async = true, lsp_format = "fallback" })
            end,
            mode = "",
            desc = "Format buffer",
        },
    },
    opts = {
        formatters_by_ft = {
            lua = { "stylua" },
            python = { "black" },
            javascript = { "prettier" },
            typescript = { "prettier" },
            javascriptreact = { "prettier" },
            typescriptreact = { "prettier" },
            css = { "prettier" },
            html = { "prettier" },
            json = { "prettier" },
            yaml = { "prettier" },
            go = { "gofmt" },
            rust = { "rustfmt" },
            c = { "clang-format" },
            cpp = { "clang-format" },
        },
        format_on_save = {
            timeout_ms = 2000,
            lsp_format = "fallback",
        },
    },
}
