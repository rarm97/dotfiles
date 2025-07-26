    print("telescope setup run")
return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = "Telescope",
  config = function()
    require("telescope").setup({
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        mappings = {
          i = {
            ["<esc>"] = require("telescope.actions").close,  
            ["<C-j>"] = "move_selection_next",
            ["<C-k>"] = "move_selection_previous",
        },
        },
      },
    })
  end,
}
