return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  config = function()
    local harpoon = require("harpoon")

    harpoon:setup()

    local keymap = vim.keymap.set
    local opts = { noremap = true, silent = true }

    keymap("n", "<leader>a", function() harpoon:list():add() end, vim.tbl_extend("force", opts, { desc = "Harpoon: Add file" }))
    keymap("n", "<C-e>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, vim.tbl_extend("force", opts, { desc = "Harpoon: Quick menu" }))

    keymap("n", "<leader>1", function() harpoon:list():select(1) end, { desc = "Harpoon: Go to file 1" })
    keymap("n", "<leader>2", function() harpoon:list():select(2) end, { desc = "Harpoon: Go to file 2" })
    keymap("n", "<leader>3", function() harpoon:list():select(3) end, { desc = "Harpoon: Go to file 3" })
    keymap("n", "<leader>4", function() harpoon:list():select(4) end, { desc = "Harpoon: Go to file 4" })
  end,
}
