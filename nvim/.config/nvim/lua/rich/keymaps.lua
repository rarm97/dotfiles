local opts = { noremap = true, silent = true }

-- Save current file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", opts)

-- Close current buffer (never exits Neovim)
vim.keymap.set("n", "<leader>q", "<cmd>bd<cr>", { desc = "Close buffer" })

-- Hard quit Neovim
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit Neovim" })

-- Open netrw file browser
vim.keymap.set("n", "<leader>e", "<cmd>Ex<cr>", { desc = "Open netrw" })

-- Git Fugitive
vim.keymap.set("n", "<leader>gs", "<cmd>Git<cr>", { desc = "Fugitive: Git Status" })

-- Move selected lines up/down in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Join lines without moving cursor
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines, keep cursor" })

-- Half-page jump + center
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half-page down + center" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half-page up + center" })

-- Search next/prev + center + unfold
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search + center" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search + center" })

-- Paste over selection without losing register
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste without register loss" })

-- Yank to system clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to clipboard" })

-- Delete to void register
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete to void register" })

-- Disable Q (ex mode)
vim.keymap.set("n", "Q", "<nop>")

-- Search-replace word under cursor
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Replace word under cursor" })

-- Make current file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "chmod +x current file" })
