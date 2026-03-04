-- Lazydev: proper Neovim Lua API completions when editing your config.
-- Automatically configures lua_ls to understand vim.*, lazy.nvim specs,
-- and plugin APIs without manual workspace.library paths.
return {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
        library = {
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        },
    },
}
