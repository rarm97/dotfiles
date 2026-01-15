return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
  },

  keys = {
    { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "Find files" },
    { "<leader>fg", function() require("telescope.builtin").live_grep() end,  desc = "Live grep" },
    { "<leader>fb", function() require("telescope.builtin").buffers() end,    desc = "Buffers" },
    { "<leader>fh", function() require("telescope.builtin").help_tags() end,  desc = "Help tags" },
    { "<leader>fe", function() require("telescope").extensions.file_browser.file_browser() end, desc = "File browser" },
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

      -- Put find_files override here (reliable)
      pickers = {
        find_files = {
          hidden = true,
          find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*", "." },
        },
      },

      extensions = {
        file_browser = {
          hidden = true,
          layout_strategy = "horizontal",
          layout_config = { height = 0.3 },
        },
      },
    })

    telescope.load_extension("file_browser")
  end,
}
