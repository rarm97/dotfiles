-- Save current file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { silent = true, desc = "Write file" })

-- Close current buffer (never exits Neovim)
vim.keymap.set("n", "<leader>q", "<cmd>bd<cr>", { silent = true, desc = "Close buffer" })

-- Hard quit Neovim
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { silent = true, desc = "Quit Neovim" })

-- Open netrw file browser
vim.keymap.set("n", "<leader>e", "<cmd>Ex<cr>", { silent = true, desc = "Open netrw" })

-- Git Fugitive
vim.keymap.set("n", "<leader>gs", "<cmd>Git<cr>", { silent = true, desc = "Fugitive: Git Status" })

-- Move selected lines up/down in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true, desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true, desc = "Move selection up" })

-- Join lines without moving cursor
vim.keymap.set("n", "J", "mzJ`z", { silent = true, desc = "Join lines, keep cursor" })

-- Half-page jump + center
vim.keymap.set("n", "<C-d>", "<C-d>zz", { silent = true, desc = "Half-page down + center" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { silent = true, desc = "Half-page up + center" })

-- Search next/prev + center + unfold
vim.keymap.set("n", "n", "nzzzv", { silent = true, desc = "Next search + center" })
vim.keymap.set("n", "N", "Nzzzv", { silent = true, desc = "Prev search + center" })

-- Clear search highlights
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { silent = true, desc = "Clear search highlights" })

-- Paste over selection without losing register
vim.keymap.set("x", "<leader>p", [["_dP]], { silent = true, desc = "Paste without register loss" })

-- Yank to system clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { silent = true, desc = "Yank to clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { silent = true, desc = "Yank line to clipboard" })

-- Delete to void register
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { silent = true, desc = "Delete to void register" })

-- Disable Q (ex mode)
vim.keymap.set("n", "Q", "<nop>")

-- Search-replace word under cursor
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
    { desc = "Replace word under cursor" })

-- Make current file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "chmod +x current file" })
