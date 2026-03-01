-- Editor options: appearance, indentation, search, splits, and persistence.

-- Appearance
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"          -- always show, avoids layout shift from diagnostics/gitsigns
vim.opt.cursorline = true
vim.opt.guicursor = ""              -- block cursor in all modes
vim.opt.colorcolumn = "80"

-- Indentation (4 spaces, no tabs)
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false

-- Scrolling: keep 12 lines visible above/below cursor
vim.opt.scrolloff = 12

-- Search: highlight matches but clear with <Esc> (see keymaps.lua)
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Splits open to the right/below (feels more natural)
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Faster UI updates (default 4000ms is too sluggish for gitsigns/lsp)
vim.opt.updatetime = 50

-- Persistence: no swap/backup, but persistent undo across sessions
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = vim.fn.stdpath("state") .. "/undo"
vim.opt.undofile = true

-- Show absolute line numbers in insert mode (easier to reference specific lines)
-- and relative numbers in normal mode (easier for jump counts like 5j)
local augroup = vim.api.nvim_create_augroup("rich-options", { clear = true })

vim.api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    callback = function()
        vim.wo.relativenumber = false
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
        vim.wo.relativenumber = true
    end,
})
