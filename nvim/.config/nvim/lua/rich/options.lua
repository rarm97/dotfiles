vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50
vim.opt.cursorline = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.clipboard = "unnamedplus"

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    vim.opt.relativenumber = false
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    vim.opt.relativenumber = true
  end,
})

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
