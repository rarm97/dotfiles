vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Netrw settings
vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25

require("rich.options")
require("rich.lazy")
require("rich.layout.colourscheme")
require("rich.keymaps")

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("rich-highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank({ higroup = "IncSearch", timeout = 40 })
    end,
})

-- Strip trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("rich-trim-whitespace", { clear = true }),
    pattern = "*",
    command = [[%s/\s\+$//e]],
})
