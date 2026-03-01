-- Bootstrap lazy.nvim (plugin manager): auto-clones on first run,
-- then loads all plugin specs from lua/rich/plugins/*.lua.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = {
        { import = "rich.plugins" },
    }
})
