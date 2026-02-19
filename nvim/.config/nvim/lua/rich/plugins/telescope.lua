return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  keys = {
    { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "Find files" },
    { "<leader>fg", function() require("telescope.builtin").live_grep() end,  desc = "Live grep" },
    { "<leader>fb", function() require("telescope.builtin").buffers() end,    desc = "Buffers" },
    { "<leader>fh", function() require("telescope.builtin").help_tags() end,  desc = "Help tags" },
  },

  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
      defaults = {
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
            ["<CR>"]  = actions.select_default,
          },
          n = {
            ["<CR>"] = actions.select_default,
          },
        },

        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
      },

      pickers = {
        find_files = {
          hidden = true,
          find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*", "." },
        },
      },
    })
  end,
}
