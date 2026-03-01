-- Lualine: statusline showing mode, git branch, diagnostics, and file info.
-- Uses the rose-pine theme to match the colour scheme.
-- Minimal separators to keep it clean.
return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
        options = {
            theme = "rose-pine",
            component_separators = { left = "|", right = "|" },
            section_separators = { left = "", right = "" },
        },
        sections = {
            lualine_a = { "mode" },
            lualine_b = { "branch", "diff", "diagnostics" },
            lualine_c = { { "filename", path = 1 } },
            lualine_x = { "filetype" },
            lualine_y = { "progress" },
            lualine_z = { "location" },
        },
    },
}
