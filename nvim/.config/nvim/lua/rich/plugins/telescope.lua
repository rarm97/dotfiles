return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim"
  },
  keys = {
    { "<leader>ff", desc = "Find files" },
    { "<leader>fg", desc = "Live grep" },
    { "<leader>fb", desc = "Buffers" },
    { "<leader>fh", desc = "Help tags" },
    { "<leader>fe", desc = "File browser" },
  },

  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
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
        vimgrep_arguments = {
          "rg",
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
          "--hidden",
          "--glob",
          "!.git/*",
        },
        mappings = {
          i = {
            ["<esc>"] = actions.close,
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
          },
        },
      },
      extensions = {
        file_browser = {
            hidden = true, 
            layout_strategy = "horizontal",
            layout_config = {height = 0.3},
        }
      },
    })

    -- *** Load the file_browser extension *after* setup ***
    require("telescope").load_extension("file_browser")
  end,
}
