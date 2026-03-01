-- Harpoon: bookmark up to 4 files for instant switching.
-- Faster than telescope for files you're actively working on.
-- <leader>ha to mark, <leader>h1-4 to jump, <leader>hh for the menu.
return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },

    config = function()
        local harpoon = require("harpoon")
        harpoon:setup()
        local list = harpoon:list()

        vim.keymap.set("n", "<leader>ha", function() list:add() end, { desc = "Harpoon: Add file" })
        vim.keymap.set("n", "<leader>hr", function() list:remove() end, { desc = "Harpoon: Remove file" })
        vim.keymap.set("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(list) end, { desc = "Harpoon: Quick Menu" })

        vim.keymap.set("n", "<leader>h1", function() list:select(1) end, { desc = "Harpoon: Go to file 1" })
        vim.keymap.set("n", "<leader>h2", function() list:select(2) end, { desc = "Harpoon: Go to file 2" })
        vim.keymap.set("n", "<leader>h3", function() list:select(3) end, { desc = "Harpoon: Go to file 3" })
        vim.keymap.set("n", "<leader>h4", function() list:select(4) end, { desc = "Harpoon: Go to file 4" })
    end,
}
