local opts = { noremap = true, silent = true }
-- Save current file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", opts)

-- Close current buffer (never exits Neovim)
vim.keymap.set("n", "<leader>q", "<cmd>bd<cr>", { desc = "Close buffer" })

-- Optional: hard quit Neovim (explicit)
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit Neovim" })

-- Open netrw (new file browser now neo-tree has gone)
vim.keymap.set("n", "<leader>e", "<cmd>Ex<cr>", { desc = "Open netrw" })

-- Git Fugative
vim.keymap.set("n", "<leader>gs", "<cmd>Git<cr>", { desc = "Fugitive: Git Status" })
