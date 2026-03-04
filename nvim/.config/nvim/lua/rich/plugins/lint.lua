-- Linting: runs linters asynchronously on save and insert leave.
-- Separate from conform (formatting) and LSP (diagnostics).
-- Linter results show as native Neovim diagnostics.
return {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        local lint = require("lint")

        lint.linters_by_ft = {
            sh = { "shellcheck" },
            bash = { "shellcheck" },
        }

        vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
            group = vim.api.nvim_create_augroup("rich-lint", { clear = true }),
            callback = function()
                lint.try_lint()
            end,
        })
    end,
}
