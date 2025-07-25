vim.g.mapleader = " "
vim.g.maplocalleader = " "
require("rich.options")
require("rich.plugins")
require("rich.keymaps")
require("rich.layout.colorscheme")
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        require("nvim-tree.api").tree.open({ focus = true })
    end,
})
