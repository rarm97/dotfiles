-- Main orchestrator: sets leader key, configures netrw, then loads
-- options, plugins (via lazy.nvim), and keymaps in order.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Netrw: open in same window, no banner, 25% width when split
vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25

require("rich.options")
require("rich.lazy")
require("rich.keymaps")

-- Brief flash on yank so you can see what was copied
vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("rich-highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
    end,
})

-- Strip trailing whitespace on save (only for files without a conform formatter)
vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("rich-trim-whitespace", { clear = true }),
    pattern = "*",
    callback = function(args)
        local ok, conform = pcall(require, "conform")
        if ok then
            local formatters = conform.list_formatters(args.buf)
            if #formatters > 0 then
                return
            end
        end
        local pos = vim.api.nvim_win_get_cursor(0)
        vim.cmd([[%s/\s\+$//e]])
        vim.api.nvim_win_set_cursor(0, pos)
    end,
})
