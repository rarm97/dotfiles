-- Global keymaps (not tied to any plugin).
-- Plugin-specific keymaps live in their respective plugin files.
-- All mappings use desc so they show up in which-key.

-- Basics
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { silent = true, desc = "Write file" })
vim.keymap.set("n", "<leader>q", "<cmd>bd<cr>", { silent = true, desc = "Close buffer" })
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { silent = true, desc = "Quit Neovim" })
vim.keymap.set("n", "<leader>e", "<cmd>Ex<cr>", { silent = true, desc = "Open netrw" })

-- Move selected lines up/down and re-indent
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true, desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true, desc = "Move selection up" })

-- Join lines without moving cursor (mark position, join, restore)
vim.keymap.set("n", "J", "mzJ`z", { silent = true, desc = "Join lines, keep cursor" })

-- Half-page jumps stay centred so you don't lose your place
vim.keymap.set("n", "<C-d>", "<C-d>zz", { silent = true, desc = "Half-page down + center" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { silent = true, desc = "Half-page up + center" })

-- Search results stay centred and unfold any folds
vim.keymap.set("n", "n", "nzzzv", { silent = true, desc = "Next search + center" })
vim.keymap.set("n", "N", "Nzzzv", { silent = true, desc = "Prev search + center" })

-- Clear search highlights (hlsearch is on; Esc dismisses them)
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { silent = true, desc = "Clear search highlights" })

-- Clipboard: yanks stay in vim registers by default (clipboard=unnamedplus is off).
-- Use leader-y for intentional clipboard copies, leader-d to delete without
-- polluting any register, leader-p to paste over a selection without losing
-- what's in the register.
vim.keymap.set("x", "<leader>p", [["_dP]], { silent = true, desc = "Paste without register loss" })
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { silent = true, desc = "Yank to clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { silent = true, desc = "Yank line to clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { silent = true, desc = "Delete to void register" })

-- Quickfix list navigation
vim.keymap.set("n", "]q", "<cmd>cnext<cr>zz", { silent = true, desc = "Next quickfix item" })
vim.keymap.set("n", "[q", "<cmd>cprev<cr>zz", { silent = true, desc = "Prev quickfix item" })

-- Disable Q (ex mode is never useful, easy to hit accidentally)
vim.keymap.set("n", "Q", "<nop>")

-- Quick search-replace for the word under cursor across the whole file
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
    { desc = "Replace word under cursor" })

-- Make current file executable without leaving the editor
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "chmod +x current file" })
