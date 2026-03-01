-- Trouble: project-wide diagnostics list (errors, warnings, etc.).
-- Better than the default quickfix list. Toggle with <leader>tt,
-- navigate with [t / ]t.
return {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
        { "<leader>tt", "<cmd>Trouble diagnostics toggle<cr>", desc = "Trouble: Toggle" },
        {
            "[t",
            function()
                local trouble = require("trouble")
                trouble.prev({ skip_groups = true, jump = true })
            end,
            desc = "Trouble: Prev item",
        },
        {
            "]t",
            function()
                local trouble = require("trouble")
                trouble.next({ skip_groups = true, jump = true })
            end,
            desc = "Trouble: Next item",
        },
    },
}
