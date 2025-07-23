require("rich.options")
require("rich.keymaps.global")
require("rich.lazy")
require("nvim-treesitter.configs").setup({
    ensure_installed = {
        "lua",
        "rust",
        "bash",
        "javascript",
        "python",
        "json",
        "toml",
        "markdown",
        "vim", 
        "rust"
    }, 
    highlight = {
        enable = true,
    }, 
    indent = {
        enable = true, 
    },
})

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        require("nvim-tree.api").tree.open({ focus = true })
    end,
})
