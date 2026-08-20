-- Lualine: statusline showing mode, git branch, diagnostics, and file info.
-- Uses the rose-pine theme to match the colour scheme.
-- Minimal separators to keep it clean.
return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
        -- Refresh lualine when macro recording starts/stops. Grouped, like every
        -- other autocmd in this config, so reloading the plugin replaces these
        -- rather than stacking a second copy that refreshes twice per keystroke.
        local group = vim.api.nvim_create_augroup("rich-lualine-recording", { clear = true })
        vim.api.nvim_create_autocmd("RecordingEnter", {
            group = group,
            callback = function() require("lualine").refresh() end,
        })
        vim.api.nvim_create_autocmd("RecordingLeave", {
            group = group,
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
                        function()
                            local reg = vim.fn.reg_recording()
                            return reg ~= "" and ("recording @" .. reg) or ""
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
