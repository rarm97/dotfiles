return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  lazy = false,
  config = function()
    local harpoon = require("harpoon")
    harpoon:setup()
    local list = harpoon:list()
    local opts = { noremap = true, silent = true }

    -- Add current file to Harpoon
    vim.keymap.set("n", "<leader>ha", function() list:add() end, vim.tbl_extend("force", opts, { desc = "Harpoon: Add file" }))

    -- Remove current file from Harpoon
    vim.keymap.set("n", "<leader>hr", function() list:remove() end, vim.tbl_extend("force", opts, { desc = "Harpoon: Remove file" }))

    -- Toggle Harpoon menu (Primeagen now does this via :Harpoon)
    vim.keymap.set("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(list) end, vim.tbl_extend("force", opts, { desc = "Harpoon: Quick Menu" }))

    -- Navigate to Harpoon files
    vim.keymap.set("n", "<leader>1", function() list:select(1) end, { desc = "Harpoon: Go to file 1" })
    vim.keymap.set("n", "<leader>2", function() list:select(2) end, { desc = "Harpoon: Go to file 2" })
    vim.keymap.set("n", "<leader>3", function() list:select(3) end, { desc = "Harpoon: Go to file 3" })
    vim.keymap.set("n", "<leader>4", function() list:select(4) end, { desc = "Harpoon: Go to file 4" })
  end,
}
