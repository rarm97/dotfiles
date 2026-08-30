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

-- Line wrap, on deliberately.
--
-- Neovim's default for 'wrap' is ON, so `false` here was never a default being
-- kept -- it was the option being actively turned off. This file shipped `true`
-- and commit 0bdf224 ("Resolved LSP errors and hardened colorscheme.lua") left
-- it `false`, alongside three other silent value changes in the same diff
-- (tabstop, shiftwidth, updatetime). Nothing noticed: the file still parses,
-- nvim still starts, every check stayed green, and the only symptom is long
-- lines running off the right of the screen -- which reads as a preference
-- rather than a regression. So the polarity is
-- asserted now rather than assumed: checks/repo.sh reads this line on every
-- commit, and tests/test-nvim.sh reads the value back out of a running nvim.
vim.opt.wrap = true

-- Hard wrap at 80 columns, everywhere.
--
-- 'wrap' above is display-only: it folds a long line at the WINDOW edge, which
-- on a wide terminal is 156 columns, and a window edge is not a line length.
-- 'textwidth' is the one that actually keeps a line to 80, by putting a real
-- break in the file -- which is how the prose in this repo is already written.
--
-- Setting the option is NOT enough to get this everywhere, and the reason is
-- worth writing down because it is invisible until you look. 't' is the
-- formatoptions flag that breaks a line as you type; Neovim's own ftplugins
-- strip it for several filetypes, and gitcommit sets its own textwidth on top.
-- Measured on a stock nvim 0.11.6 with textwidth unset, which is the state
-- these ftplugins were written against:
--
--   lua jcroql   sh jcroql   yaml jcroql   json cqj   vim jcroql    -- no 't'
--   markdown jtcqln   text tcqj   python tcqj   rst jtcroql         -- 't' kept
--   gitcommit textwidth=72 (unconditional)
--   vim       textwidth=78 only when textwidth is still 0, so once the line
--             below runs it never fires -- gitcommit is the only real rival
--
-- ftplugins run on FileType, so a plain assignment here loses to them for lua
-- and sh -- the two languages this repo is mostly written in. The autocmd below
-- writes after they do. The bare assignment still earns its place: it covers a
-- buffer that never gets a filetype, for which FileType never fires.
vim.opt.textwidth = 80

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

-- Hold textwidth=80 and auto-wrap against the ftplugins that would undo them.
-- See the textwidth comment above for the measured list of which filetypes
-- strip 't' and which set a textwidth of their own. This runs on FileType,
-- after the ftplugin for that filetype has had its turn, so it is the last
-- write and therefore the one that counts.
--
-- opt_local, not opt: these are buffer-local options and this fires per buffer.
vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    callback = function()
        vim.opt_local.textwidth = 80
        vim.opt_local.formatoptions:append("t")
    end,
})

-- Diagnostics
--
-- Neovim's own default is virtual_text = false, so a diagnostic shows up only as
-- a sign and an underline and you have to open a float to find out what it says.
-- Verified with :lua =vim.diagnostic.config() on a config that set nothing here.
--
-- severity_sort makes the worst problem on a line the one that gets displayed,
-- rather than whichever server reported first.
vim.diagnostic.config({
    severity_sort = true,
    virtual_text = { prefix = "●", spacing = 2 },
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = "󰅚 ",
            [vim.diagnostic.severity.WARN] = "󰀪 ",
            [vim.diagnostic.severity.INFO] = "󰋽 ",
            [vim.diagnostic.severity.HINT] = "󰌶 ",
        },
    },
    float = { border = "rounded", source = true },
})
