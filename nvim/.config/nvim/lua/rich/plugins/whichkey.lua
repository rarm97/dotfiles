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
        },
    },
}
