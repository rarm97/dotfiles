-- Lualine: statusline showing mode, git branch, diagnostics, and file info.
-- Uses the rose-pine theme to match the colour scheme.
-- Minimal separators to keep it clean.
return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
        -- Refresh lualine when macro recording starts/stops
        vim.api.nvim_create_autocmd("RecordingEnter", {
            callback = function() require("lualine").refresh() end,
        })
        vim.api.nvim_create_autocmd("RecordingLeave", {
            callback = function()
                vim.defer_fn(function() require("lualine").refresh() end, 50)
            end,
        })

        require("lualine").setup({
            options = {
                theme = "rose-pine",
                component_separators = { left = "|", right = "|" },
                section_separators = { left = "", right = "" },
            },
            sections = {
                lualine_a = { "mode" },
                lualine_b = { "branch", "diff", "diagnostics" },
                lualine_c = { { "filename", path = 1 } },
                lualine_x = {
                    {
                        "macro-recording",
                        fmt = function()
                            local reg = vim.fn.reg_recording()
                            if reg ~= "" then return "recording @" .. reg end
                            return ""
                        end,
                    },
                    "searchcount",
                    "filetype",
                },
                lualine_y = { "progress" },
                lualine_z = { "location" },
            },
        })
    end,
}
