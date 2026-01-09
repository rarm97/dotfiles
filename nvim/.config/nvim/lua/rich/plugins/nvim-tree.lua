return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    require("nvim-tree").setup({
      filters = {
        dotfiles = false, 
        git_ignored = false, 
      },
      on_attach = require("rich.keymaps.nvim-tree").attach,
      view = {
        width = 30,
        relativenumber = true,
      },
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
    })
  end,
}
