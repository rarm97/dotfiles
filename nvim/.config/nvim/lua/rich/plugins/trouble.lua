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
