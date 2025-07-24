return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local harpoon = require("harpoon")

    harpoon:setup()

    -- Keymaps
    local keymap = vim.keymap.set
    keymap("n", "<leader>ha", function() harpoon:list():append() end, { desc = "Harpoon Add File" })
    keymap("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Harpoon Menu" })
    keymap("n", "<leader>1", function() harpoon:list():select(1) end)
    keymap("n", "<leader>2", function() harpoon:list():select(2) end)
    keymap("n", "<leader>3", function() harpoon:list():select(3) end)
    keymap("n", "<leader>4", function() harpoon:list():select(4) end)
  end,
}
