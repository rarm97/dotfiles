
-- Toggle nvim-tree
local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

keymap("n", "<leader>e", ":NvimTreeToggle<CR>", opts)
