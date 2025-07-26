local ok, telescope = pcall(require, "telescope.builtin")
if not ok then return end

-- Telescope keybinds
vim.keymap.set("n", "<leader>tt", function()
  require("telescope.builtin").find_files()
end, { desc = "Telescope: Find Files" })

vim.keymap.set("n", "<leader>tb", function()
  require("telescope.builtin").buffers()
end, { desc = "Telescope: Find Buffers" })

vim.keymap.set("n", "<leader>tg", function()
  require("telescope.builtin").live_grep()
end, { desc = "Telescope: Live Grep" })

vim.keymap.set("n", "<leader>th", function()
  require("telescope.builtin").help_tags()
end, { desc = "Telescope: Help Tags" })

vim.keymap.set("n", "<leader>e", function()
  require("telescope").extensions.file_browser.file_browser({
    layout_strategy = "horizontal",
    layout_config = { height = 0.3 },  -- 30% of the window at the bottom
    -- optionally, path = "%:p:h", cwd = vim.fn.expand("%:p:h"),
  })
end, { noremap = true, silent = true, desc = "Telescope File Browser (Bottom)" })
