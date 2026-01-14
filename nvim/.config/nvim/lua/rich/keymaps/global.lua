local opts = { noremap = true, silent = true }

-- Save current file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", opts)

-- Close current buffer (never exits Neovim)
vim.keymap.set("n", "<leader>q", "<cmd>bd<cr>", { desc = "Close buffer" })

-- Optional: hard quit Neovim (explicit)
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit Neovim" })

-- Quit current view ad delete buffer 
vim.keymap.set("n", "<leader>x", ":bd<CR>", opts)

-- move down then centre view
vim.keymap.set("n", "j", "jzz", opts)    

-- move up   then centre view
vim.keymap.set("n", "k", "kzz", opts)    

-- Visual mode indentation keeps selection
vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

-- Fast escape
vim.keymap.set("i", "jk", "<Esc>", opts)

-- Git Fugative
vim.keymap.set("n", "<leader>gs", "<cmd>Git<cr>", { desc = "Fugitive: Git Status" })
