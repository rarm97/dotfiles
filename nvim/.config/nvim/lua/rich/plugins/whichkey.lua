-- Which-key: shows a popup of available keybindings when you press <leader>
-- and pause. Groups organise related bindings (e.g. <leader>f = Find,
-- <leader>g = Git). Makes the config self-documenting.
return {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        spec = {
            { "<leader>f", group = "Find" },
            { "<leader>g", group = "Git" },
            { "<leader>gh", group = "Git hunks" },
            { "<leader>h", group = "Harpoon" },
            { "<leader>c", group = "Code" },
            { "<leader>t", group = "Trouble" },
            { "<leader>l", group = "LSP" },
            { "<leader>9", group = "99 (AI)" },
        },
    },
}
