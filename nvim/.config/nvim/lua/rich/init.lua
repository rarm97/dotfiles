require("rich.options")
require("rich.keymaps")
require("rich.plugins")
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        require("nvim-tree.api").tree.open({ focus = true })
    end,
})
