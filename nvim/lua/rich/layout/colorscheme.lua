-- Set Neovim colorscheme
vim.opt.termguicolors = true
vim.opt.background = "dark"

local colorscheme = "tokyonight"
local ok = pcall(vim.cmd, "colorscheme " .. colorscheme)
if not ok then
  vim.notify("Colorscheme " .. colorscheme .. " not found!", vim.log.levels.WARN)
end
