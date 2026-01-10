local ok, telescope = pcall(require, "telescope.builtin")
if not ok then return end


-- Telescope keybinds
vim.keymap.set("n", "<leader>ff", function()
    telescope.find_files ({
        hidden = true,
    })
end, { desc = "Telescope: Find Files",
})

vim.keymap.set("n", "<leader>fg", telescope.live_grep, {
    desc = "Telescope: Live Grep",
})

vim.keymap.set("n", "<leader>fb", telescope.buffers, {
    desc = "Telescope: Find Buffers",
})

vim.keymap.set("n", "<leader>fh", telescope.help_tags, {
    desc = "Telescope: File Help Tags",
})

vim.keymap.set("n", "<leader>fe", function()
  require("telescope").extensions.file_browser.file_browser({
    hidden = true,
    layout_strategy = "horizontal",
    layout_config = { height = 0.3 },  -- 30% of the window at the bottom
  })
end, { desc = "Telescope File Browser (Bottom)" })
