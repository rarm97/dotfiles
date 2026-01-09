return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim"
  },
  cmd = "Telescope",
  config = function()
    require("telescope").setup({
      defaults = {
        hidden = true, 
        find_command = {
          "rg",
          "--files",
          "--hidden",
          "--glob",
          "!.git/*",
        },
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
      extensions = {
        file_browser = {
          -- Optional: custom config for file_browser
            layout_strategy = "horizontal",
            layout_config = {height = 0.3},
        }
      },
    })

    -- *** Load the file_browser extension *after* setup ***
    require("telescope").load_extension("file_browser")
  end,
}
