-- Harpoon v2 setup
local ok, harpoon = pcall(require, "harpoon")
if not ok then
  print("Harpoon not found")
  return
end

harpoon:setup()  -- initialize Harpoon

-- Import modules
local mark = harpoon.mark
local ui = harpoon.ui

-- Options
local opts = { noremap = true, silent = true }

-- Add file
vim.keymap.set("n", "<leader>a", mark.add_file, vim.tbl_extend("force", opts, { desc = "Harpoon: Add file" }))

-- Toggle quick menu
vim.keymap.set("n", "<C-e>", ui.toggle_quick_menu, vim.tbl_extend("force", opts, { desc = "Harpoon: Quick menu" }))

-- Navigate to files
vim.keymap.set("n", "<C-h>", function() ui.nav_file(1) end, { desc = "Harpoon: Go to file 1" })
vim.keymap.set("n", "<C-j>", function() ui.nav_file(2) end, { desc = "Harpoon: Go to file 2" })
vim.keymap.set("n", "<C-k>", function() ui.nav_file(3) end, { desc = "Harpoon: Go to file 3" })
vim.keymap.set("n", "<C-l>", function() ui.nav_file(4) end, { desc = "Harpoon: Go to file 4" })
