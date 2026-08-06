-- Bootstrap lazy.nvim (plugin manager): auto-clones on first run,
-- then loads all plugin specs from lua/rich/plugins/*.lua.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        lazypath,
    })
    -- Check the clone actually worked. Without this a first run with no network
    -- (or a git that is not on PATH yet) carries on regardless: the rtp prepend
    -- points at nothing, require("lazy") throws, and nvim comes up with none of
    -- the config loaded and no obvious reason why.
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any key to exit nvim." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = {
        { import = "rich.plugins" },
    }
})
