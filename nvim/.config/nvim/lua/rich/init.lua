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
        vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
    end,
})

-- Strip trailing whitespace on save (only for files without a conform formatter)
vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("rich-trim-whitespace", { clear = true }),
    pattern = "*",
    callback = function(args)
        -- The :%s below edits whatever buffer is CURRENT, not args.buf, so bail
        -- out when they differ (:bufdo w, nvim_buf_call, a plugin writing in the
        -- background) rather than trimming the wrong file.
        if args.buf ~= vim.api.nvim_get_current_buf() then
            return
        end

        -- And a non-modifiable buffer throws E21 straight out of the autocmd,
        -- which aborts the write and prints a stack trace. Reproduces with
        -- `nvim -c 'checkhealth vim.lsp' -c 'w out.txt'`.
        if not vim.bo[args.buf].modifiable then
            return
        end

        local ok, conform = pcall(require, "conform")
        if ok and #conform.list_formatters(args.buf) > 0 then
            return
        end

        -- winsaveview rather than just the cursor: :%s can scroll the window,
        -- and restoring a cursor column that sat inside whitespace we just
        -- removed puts it past the end of the line. keeppatterns stops the trim
        -- pattern becoming the last search pattern, which would otherwise land
        -- in the / history and light up under hlsearch.
        local view = vim.fn.winsaveview()
        vim.cmd([[keeppatterns %s/\s\+$//e]])
        vim.fn.winrestview(view)
    end,
})
