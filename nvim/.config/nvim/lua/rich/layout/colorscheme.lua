-- Set Neovim colorscheme
local colorscheme = "tokyonight"
local ok, _ = pcall(vim.cmd, "colorscheme " .. colorscheme)
if not ok then
  vim.notify("Colorscheme " .. colorscheme .. " not found!", vim.log.levels.WARN)
end
