vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.scrolloff = 12
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50
vim.opt.cursorline = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.clipboard = "unnamedplus"
vim.opt.guicursor = ""
vim.opt.colorcolumn = "80"

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    vim.wo.relativenumber = false
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    vim.wo.relativenumber = true
  end,
})


