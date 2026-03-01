-- Rosé Pine Moon: dark theme with muted pastels.
-- Loaded eagerly (priority 1000) so it's available before any UI renders.
-- Transparent backgrounds let the terminal's own background show through.
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

        vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    end,
}
