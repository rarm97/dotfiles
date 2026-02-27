return {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    lazy = false,
    config = function()
        require("rose-pine").setup({
            variant = "moon",
        })

        vim.cmd("colorscheme rose-pine-moon")

        -- Transparent backgrounds (Primeagen's ColorMyPencils)
        vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    end,
}
