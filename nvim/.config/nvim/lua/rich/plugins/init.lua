-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)


vim.opt.number = true
vim.opt.relativenumber = true

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

-- collect plugin modules
require("lazy").setup({
  require("rich.plugins.lazy"),        -- lazy.nvim core settings
  require("rich.plugins.telescope"),   -- fuzzy finder
  require("rich.plugins.nvim-tree"),   -- file explorer
  require("rich.plugins.treesitter"),  -- syntax highlighting
  require("rich.plugins.fugitive"),    -- git wrapper
  require("rich.plugins.tokyonight"),   -- display handler
  require("rich.plugins.lualine"),
})
